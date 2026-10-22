//
//  DrawingShareSheet.swift
//  Twofold
//
//  Sharing a drawing, or both (SHARE_REDESIGN.md §4): as a share card in Deck colour, Night or
//  Paper, or as die-cut stickers for an Instagram story. Card and Sticker previews are the same
//  360 × 450pt frame, so switching between them never moves anything else on the screen.
//

import PostHog
import SwiftUI
import UniformTypeIdentifiers

struct DrawingShareSheet: View {
    struct Pad {
        let person: Person
        let url: URL?
        /// An image already in hand (the editor's unsaved canvas), used instead of loading `url`.
        var image: UIImage? = nil
    }

    let pads: [Pad]

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable { case card = "Card", sticker = "Sticker" }

    @State private var mode: Mode = .card
    @State private var look: ShareCardStyle = .deck
    /// The pads that have something drawn on them, loaded.
    @State private var drawings: [GameShareContent.Drawing] = []
    @State private var stickers: [UIImage] = []
    @State private var cardImage: UIImage?
    @State private var isLoading = true
    @State private var confirmation: String?
    @State private var instagramAvailable = false
    @State private var screenWidth: CGFloat = 393

    private var isBoth: Bool { pads.count > 1 }
    private var lookKey: String { "share.cardLook.\(appModel.currentUser.id.uuidString)" }
    private var scale: CGFloat { min(1, (screenWidth - 2 * Theme.Spacing.md) / GameShareCard.size.width) }

    var body: some View {
        VStack(spacing: 0) {
            ShareSheetHeader(title: isBoth ? "Share drawings" : "Share drawing") { dismiss() }

            ScrollView {
                VStack(spacing: 0) {
                    TwofoldSegmentedControl(
                        selection: $mode,
                        options: Mode.allCases.map { ($0, String(localized: String.LocalizationValue($0.rawValue))) },
                        accessibilityLabel: "Share as",
                        segmentHeight: 36
                    )
                    .frame(width: 232)
                    .padding(.top, 16)

                    preview
                        .frame(width: GameShareCard.size.width, height: GameShareCard.size.height)
                        .scaleEffect(scale)
                        .frame(height: GameShareCard.size.height * scale)
                        .padding(.top, 16)

                    Group {
                        if mode == .card {
                            TwofoldSegmentedControl(
                                selection: $look,
                                options: ShareCardStyle.allCases.map { ($0, $0.rawValue) },
                                accessibilityLabel: "Card style",
                                segmentHeight: 40
                            )
                            .padding(.horizontal, Theme.Spacing.lg)
                        } else {
                            Text(isBoth
                                 ? "Two stickers, placed together · move each one in your story"
                                 : "Transparent with a white edge · drag it anywhere in your story")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }
                    }
                    .padding(.top, 18)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { screenWidth = $0 }

            actions
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.sm)
        }
        .background(ScreenBackground())
        .overlay(alignment: .bottom) {
            if let confirmation {
                ShareConfirmation(message: confirmation)
                    .padding(.bottom, 140)
                    .transition(.opacity)
            }
        }
        .onAppear {
            instagramAvailable = InstagramStories.isAvailable
            if let raw = UserDefaults.standard.string(forKey: lookKey), let saved = ShareCardStyle(rawValue: raw) {
                look = saved
            }
        }
        .onChange(of: look) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: lookKey)
        }
        .task { await load() }
        .task(id: look) {
            guard !drawings.isEmpty else { return }
            cardImage = card?.renderedImage()
        }
        .postHogScreenView("Drawing Pad: Share")
    }

    // MARK: - Preview

    private var card: GameShareCard? {
        guard !drawings.isEmpty else { return nil }
        return GameShareCard(kind: .drawing, look: look, content: .drawings(drawings), me: appModel.currentUser, partner: appModel.partner)
    }

    @ViewBuilder
    private var preview: some View {
        if isLoading {
            ProgressView()
        } else if drawings.isEmpty {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "pencil.and.scribble")
                    .font(.largeTitle)
                Text("Nothing drawn yet")
            }
            .foregroundStyle(Theme.textSecondary)
        } else if mode == .card, let card {
            card.shadow(color: .black.opacity(0.45), radius: 18, y: 16)
        } else {
            stickerPreview
        }
    }

    private var stickerPreview: some View {
        ZStack {
            if stickers.count >= 2 {
                stickerView(stickers[0], maxSize: CGSize(width: 200, height: 300), angle: -8)
                    .offset(x: -64, y: -30)
                stickerView(stickers[1], maxSize: CGSize(width: 200, height: 300), angle: 6)
                    .offset(x: 64, y: 40)
            } else if let sticker = stickers.first {
                stickerView(sticker, maxSize: CGSize(width: 300, height: 390), angle: -4)
            } else {
                ProgressView()
            }
        }
        .frame(width: GameShareCard.size.width, height: GameShareCard.size.height)
        .background(Checkerboard())
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.Share.nightLine, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ListFormatter.localizedString(byJoining: drawings.map { String(localized: "\($0.name)'s drawing") }))
    }

    private func stickerView(_ image: UIImage, maxSize: CGSize, angle: Double) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
            .rotationEffect(.degrees(angle))
            .shadow(color: Theme.Share.stickerShadowStrong, radius: 7, y: 8)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if mode == .card {
                if let cardImage {
                    ShareLink(item: Image(uiImage: cardImage), preview: SharePreview("Drawing", image: Image(uiImage: cardImage))) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.twofoldPrimary)
                } else {
                    disabledPrimary("Share image", icon: "square.and.arrow.up")
                }
                ShareTextButton(title: "Save to Photos") {
                    if let cardImage { save([cardImage]) }
                }
                .disabled(cardImage == nil)
            } else {
                if stickers.isEmpty {
                    disabledPrimary(instagramAvailable ? "Add to Instagram story" : "Share sticker", icon: instagramAvailable ? "plus.square" : "square.and.arrow.up")
                } else if instagramAvailable {
                    Button(action: shareToInstagram) {
                        Label("Add to Instagram story", systemImage: "plus.square")
                    }
                    .buttonStyle(.twofoldPrimary)
                } else {
                    // Without Instagram, the system share sheet, with each sticker as its own PNG.
                    ShareLink(items: stickers.map { StickerPNG(image: $0) }, preview: { _ in SharePreview("Sticker") }) {
                        Label(isBoth ? "Share stickers" : "Share sticker", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.twofoldPrimary)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    ShareTextButton(title: isBoth ? "Save stickers" : "Save sticker") { save(stickers) }
                    ShareTextButton(title: isBoth ? "Copy stickers" : "Copy sticker") { copyStickers() }
                }
                .disabled(stickers.isEmpty)
            }
        }
    }

    private func disabledPrimary(_ title: LocalizedStringKey, icon: String) -> some View {
        Button {} label: { Label(title, systemImage: icon) }
            .buttonStyle(.twofoldPrimary)
            .disabled(true)
    }

    private func save(_ images: [UIImage]) {
        Task {
            do {
                for image in images { try await SharePhotoSaver.save(image) }
                confirm(String(localized: "Saved to Photos"))
            } catch {
                confirm(String(localized: "Couldn't save — allow Twofold to add photos in Settings"))
            }
        }
    }

    /// As PNGs, so they keep their transparency when pasted into Messages.
    private func copyStickers() {
        UIPasteboard.general.setItems(stickers.compactMap { $0.pngData().map { [UTType.png.identifier: $0] } })
        confirm(String(localized: "Copied"))
    }

    /// Instagram takes one sticker per story. Both drawings go as one image, placed together the way
    /// the preview shows them; saving or copying gives two that move on their own.
    private func shareToInstagram() {
        Task {
            let sticker = stickers.count >= 2 ? combinedSticker() : stickers.first
            guard let sticker else { return }
            let (top, bottom) = storyColours
            let opened = await InstagramStories.share(sticker: sticker, topColor: top, bottomColor: bottom)
            if !opened { confirm(String(localized: "Couldn't open Instagram")) }
        }
    }

    private var storyColours: (String, String) {
        switch look {
        case .deck: (Theme.Share.storyDeckTop, Theme.Share.storyDeckBottom)
        case .night: (Theme.Share.storyNight, Theme.Share.storyNight)
        case .paper: (Theme.Share.storyPaper, Theme.Share.storyPaper)
        }
    }

    @MainActor
    private func combinedSticker() -> UIImage? {
        let content = ZStack {
            stickerView(stickers[0], maxSize: CGSize(width: 200, height: 300), angle: -8).offset(x: -64, y: -30)
            stickerView(stickers[1], maxSize: CGSize(width: 200, height: 300), angle: 6).offset(x: 64, y: 40)
        }
        .frame(width: GameShareCard.size.width, height: GameShareCard.size.height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private func confirm(_ message: String) {
        withAnimation { confirmation = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { confirmation = nil }
        }
    }

    // MARK: - Loading

    private func load() async {
        await AvatarView.prefetch(appModel.currentUser)
        await AvatarView.prefetch(appModel.partner)
        var loaded: [GameShareContent.Drawing] = []
        for pad in pads {
            var image = pad.image
            if image == nil { image = await Self.load(pad.url) }
            guard let image else { continue }
            loaded.append(.init(name: pad.person.name, image: image))
        }
        drawings = loaded
        isLoading = false
        cardImage = card?.renderedImage()

        let sources = loaded.map(\.image)
        stickers = await Task.detached(priority: .userInitiated) {
            sources.compactMap { DrawingSticker.make(from: $0) }
        }.value
    }

    /// The disk copy first, which the screen this opens from has normally just shown; the network
    /// only if it isn't there.
    private static func load(_ url: URL?) async -> UIImage? {
        guard let url else { return nil }
        if let cached = RemoteImageDiskCache.image(for: url) { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }
}

/// A sticker for the system share sheet, as a PNG so its transparency survives.
private struct StickerPNG: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
    }
}
