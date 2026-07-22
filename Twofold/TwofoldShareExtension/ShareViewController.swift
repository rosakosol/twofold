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
import PDFKit

class ShareViewController: SLComposeServiceViewController {

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        Task {
            let subject = await extractSubject()
            let bodyText = await extractBodyText()
            let pdfText = await extractPDFText()

            if subject != nil || bodyText != nil || pdfText != nil {
                PendingShareStore.add(PendingFlightShare(subject: subject, bodyText: bodyText, pdfText: pdfText))
            }
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    // MARK: - Content extraction

    private var inputItems: [NSExtensionItem] {
        (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
    }

    /// Mail/Gmail/Outlook typically surface the email's subject as the share item's title,
    /// separate from `contentText`/attachments (which carry the body). Booking confirmation
    /// subjects often summarize the flight number and date even when the body is sparse.
    private func extractSubject() async -> String? {
        for item in inputItems {
            if let title = item.attributedTitle?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
        }
        return nil
    }

    /// Apple Mail typically pre-fills `contentText` with the shared body; Gmail/Outlook
    /// are less consistent, so this falls back through attachments, then HTML stripped
    /// to plain text, then a shared URL, then the item's own content text.
    private func extractBodyText() async -> String? {
        let composedText = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !composedText.isEmpty {
            return composedText
        }
        return await extractAttachmentText()
    }

    private func extractAttachmentText() async -> String? {
        for item in inputItems {
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

            if let content = item.attributedContentText?.string, !content.isEmpty {
                return content
            }
        }
        return nil
    }

    /// Only used as a fallback when subject/body don't yield a flight (see
    /// FlightEmailParsingService). Capped to avoid holding a large blob in the
    /// extension's tight memory budget.
    private func extractPDFText() async -> String? {
        let maxPDFBytes = 8 * 1024 * 1024

        for item in inputItems {
            guard let attachments = item.attachments else { continue }
            for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                guard let data = await loadData(from: provider, typeIdentifier: UTType.pdf.identifier),
                      data.count <= maxPDFBytes,
                      let document = PDFDocument(data: data),
                      let text = document.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { continue }
                return text
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

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: data)
                } else if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(returning: nil)
                }
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
