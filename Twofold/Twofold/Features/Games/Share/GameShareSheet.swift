//
//  GameShareSheet.swift
//  Twofold
//
//  Sharing a game's result (SHARE_REDESIGN.md §2): the card, page dots when a deck has more than
//  one question, Deck colour / Night / Paper, then Share image, Save to Photos and Copy as text.
//  Every game comes here, Word Guess and Sudoku included.
//

import PostHog
import SwiftUI

struct GameShareSheet: View {
    let data: GameResultShareData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var look: ShareCardStyle = .deck
    /// The current card as a PNG. Rendered after both photos are cached, and again whenever the
    /// page or the look changes.
    @State private var image: UIImage?
    /// What waits on "This includes X's answer too" while that question is up.
    @State private var pending: Action?
    @State private var confirmation: String?
    @State private var screenWidth: CGFloat = 393

    private enum Action: Identifiable {
        case share(UIImage), save(UIImage), copy
        var id: String {
            switch self {
            case .share: "share"
            case .save: "save"
            case .copy: "copy"
            }
        }
    }

    private var cards: [GameShareContent] { data.shareCards }

    /// The last look this person used, per account so a shared phone doesn't mix two people's.
    private var lookKey: String { "share.cardLook.\(data.me.id.uuidString)" }

    var body: some View {
        VStack(spacing: 0) {
            ShareSheetHeader { dismiss() }

            ScrollView {
                VStack(spacing: 0) {
                    cardPager
                        .padding(.top, 24)

                    SharePageDots(count: cards.count, current: page)
                        .padding(.top, 16)

                    TwofoldSegmentedControl(
                        selection: $look,
                        options: ShareCardStyle.allCases.map { ($0, $0.rawValue) },
                        accessibilityLabel: "Card style",
                        segmentHeight: 40
                    )
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, 18)
                }
            }
            .scrollBounceBehavior(.basedOnSize)

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
        .confirmationDialog(
            "This includes \(data.partner.name)'s answer too — share anyway?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { action in
            switch action {
            case .share(let image):
                ShareLink(item: Image(uiImage: image), preview: preview(image)) { Text("Share") }
            case .save(let image):
                Button("Save to Photos") { save(image) }
            case .copy:
                Button("Copy") { copy() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if let raw = UserDefaults.standard.string(forKey: lookKey), let saved = ShareCardStyle(rawValue: raw) {
                look = saved
            }
        }
        .onChange(of: look) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: lookKey)
        }
        .task(id: RenderKey(page: page, look: look)) {
            await AvatarView.prefetch(data.me)
            await AvatarView.prefetch(data.partner)
            image = card(at: page)?.renderedImage()
        }
        .postHogScreenView("Games: Results Share")
    }

    private struct RenderKey: Equatable {
        let page: Int
        let look: ShareCardStyle
    }

    // MARK: - Cards

    private func card(at index: Int) -> GameShareCard? {
        guard cards.indices.contains(index) else { return nil }
        return GameShareCard(kind: data.shareKind, look: look, content: cards[index], me: data.me, partner: data.partner)
    }

    /// The card at its real size, scaled down only on a phone too narrow for 360pt plus margins.
    /// The exported image is always the full 1080 × 1350px.
    private var cardPager: some View {
        let scale = min(1, (screenWidth - 2 * Theme.Spacing.md) / GameShareCard.size.width)
        return TabView(selection: $page) {
            ForEach(cards.indices, id: \.self) { index in
                card(at: index)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 16)
                    .scaleEffect(scale)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // Room for the shadow below the card.
        .frame(height: GameShareCard.size.height * scale + 40)
        .animation(reduceMotion ? nil : .default, value: page)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { screenWidth = $0 }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Group {
                if let image, !data.includesPartnerWords {
                    ShareLink(item: Image(uiImage: image), preview: preview(image)) {
                        Label("Share image", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        if let image { pending = .share(image) }
                    } label: {
                        Label("Share image", systemImage: "square.and.arrow.up")
                    }
                    .disabled(image == nil)
                }
            }
            .buttonStyle(.twofoldPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                ShareTextButton(title: "Save to Photos") {
                    guard let image else { return }
                    if data.includesPartnerWords { pending = .save(image) } else { save(image) }
                }
                .disabled(image == nil)
                ShareTextButton(title: "Copy as text") {
                    if data.includesPartnerWords { pending = .copy } else { copy() }
                }
            }
        }
    }

    private func preview(_ image: UIImage) -> SharePreview<Image, Never> {
        SharePreview("\(data.shareKind.name) result", image: Image(uiImage: image))
    }

    private func save(_ image: UIImage) {
        Task {
            do {
                try await SharePhotoSaver.save(image)
                confirm(String(localized: "Saved to Photos"))
            } catch {
                confirm(String(localized: "Couldn't save — allow Twofold to add photos in Settings"))
            }
        }
    }

    private func copy() {
        UIPasteboard.general.string = data.shareText(for: page)
        confirm(String(localized: "Copied"))
    }

    private func confirm(_ message: String) {
        withAnimation { confirmation = message }
        UIAccessibility.post(notification: .announcement, argument: message)
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { confirmation = nil }
        }
    }
}

#Preview("Deep Conversation deck") {
    GameShareSheet(data: GameResultShareData(
        gameType: .deepConversations,
        title: "Getting to Know Each Other",
        isDaily: false,
        me: MockData.dara,
        partner: MockData.rosa,
        matchPercent: nil,
        triviaMyScore: nil,
        triviaPartnerScore: nil,
        triviaTotalRounds: nil,
        deepConversationRounds: [
            GameResultShareRound(question: "What's a childhood memory that still makes you smile?", myAnswer: "Building blanket forts with my sister.", partnerAnswer: "Catching fireflies in summer."),
            GameResultShareRound(question: "What does your ideal weekend look like?", myAnswer: "Sleeping in, then a long walk somewhere new.", partnerAnswer: "Cooking a big breakfast together."),
        ],
        dailyStreak: nil
    ))
}

#Preview("Trivia") {
    GameShareSheet(data: GameResultShareData(
        gameType: .triviaBattle,
        title: "Around the World",
        isDaily: false,
        me: MockData.dara,
        partner: MockData.rosa,
        matchPercent: nil,
        triviaMyScore: 8,
        triviaPartnerScore: 6,
        triviaTotalRounds: 11,
        deepConversationRounds: nil,
        dailyStreak: nil
    ))
}
