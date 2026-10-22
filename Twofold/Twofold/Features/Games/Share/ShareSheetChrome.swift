//
//  ShareSheetChrome.swift
//  Twofold
//
//  The parts the game and flight share sheets have in common (SHARE_REDESIGN.md §2 and §4): the
//  close-and-title header, page dots, the two text buttons under the primary one, and saving a
//  PNG to Photos.
//

import Photos
import SwiftUI

/// 44pt round close button on the left, "Share" centred. Nothing else in the header.
struct ShareSheetHeader: View {
    var title: LocalizedStringKey = "Share"
    let close: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .background(Theme.raised, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }
}

/// 7pt dots, only drawn when there is more than one page. VoiceOver reads "Card 1 of 3".
struct SharePageDots: View {
    let count: Int
    let current: Int
    var noun: String = "Card"

    var body: some View {
        if count > 1 {
            HStack(spacing: 7) {
                ForEach(0..<count, id: \.self) { index in
                    Circle()
                        .fill(index == current ? Theme.textPrimary : Theme.Share.dotInactive)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(noun) \(current + 1) of \(count)")
        }
    }
}

/// "Save to Photos" and "Copy as text": accent, 15pt semibold, 44pt tall.
struct ShareTextButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

enum SharePhotoSaver {
    enum Failure: Error { case notAllowed, failed }

    /// Saves the image as a PNG, so a sticker keeps its transparent background in Photos. Asks for
    /// add-only access, which never lets the app see the library.
    static func save(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.notAllowed }
        guard let data = image.pngData() else { throw Failure.failed }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

/// The brief confirmation after Save or Copy, shown over the bottom of the sheet.
struct ShareConfirmation: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// 20pt squares, to show which parts of a sticker are transparent.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Share.checkerB))
            let side: CGFloat = 20
            for row in 0..<Int(ceil(size.height / side)) {
                for column in 0..<Int(ceil(size.width / side)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)), with: .color(Theme.Share.checkerA))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
