//
//  ShareViewController.swift
//  TwofoldShareExtension
//
//  Deliberately minimal: grab whatever text the host app handed us, queue it in the
//  App Group shared container, done. Parsing and confirmation happen back in the main
//  app (see PendingFlightShareReviewView) — this stays out of the way of the tight
//  memory/time budget share extensions run under.
//

import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        Task {
            if let text = await extractSharedText(), !text.isEmpty {
                PendingShareStore.add(PendingFlightShare(rawText: text))
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    // MARK: - Content extraction

    /// Apple Mail typically pre-fills `contentText` with the shared body; Gmail/Outlook
    /// are less consistent, so this falls back through attachments, then HTML stripped
    /// to plain text, then a shared URL, then the item's own title/subject.
    private func extractSharedText() async -> String? {
        var pieces: [String] = []

        let composedText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !composedText.isEmpty {
            pieces.append(composedText)
        }

        if pieces.isEmpty, let attachmentText = await extractAttachmentText() {
            pieces.append(attachmentText)
        }

        let combined = pieces.joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }

    private func extractAttachmentText() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        for item in items {
            if let attachments = item.attachments {
                for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = await loadText(from: provider, typeIdentifier: UTType.plainText.identifier) {
                        return text
                    }
                }
                for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                    if let html = await loadText(from: provider, typeIdentifier: UTType.html.identifier),
                       let stripped = Self.stripHTML(html) {
                        return stripped
                    }
                }
                for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        return url.absoluteString
                    }
                }
            }

            if let title = item.attributedTitle?.string, !title.isEmpty {
                return title
            }
            if let content = item.attributedContentText?.string, !content.isEmpty {
                return content
            }
        }
        return nil
    }

    private func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func stripHTML(_ html: String) -> String? {
        guard let data = html.data(using: .utf8) else { return nil }
        guard let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
            ],
            documentAttributes: nil
        ) else { return nil }
        return attributed.string
    }
}
