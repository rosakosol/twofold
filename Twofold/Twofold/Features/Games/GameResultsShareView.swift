//
//  GameResultsShareView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct GameResultsShareView: View {
    let data: GameResultShareData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var page = 0
    /// Set instead of sharing directly whenever the current layout renders the *partner's*
    /// answer text (every layout except `.scoreSnapshot` — see `GameResultShareData.availableLayouts`,
    /// only reachable when there's a real single-round Q&A to render). Mutual in-app reveal
    /// isn't the same as consent to have a partner's own words exported to Photos/Messages/
    /// Instagram, so this gates both CTAs behind a one-time-per-tap confirmation instead of
    /// sharing on the first tap the way `.scoreSnapshot` (no free text, no one else's words) can.
    @State private var pendingShareAction: PendingShareAction?

    private enum PendingShareAction {
        case instagram(UIImage)
        case other(UIImage)
    }

    /// Every layout this specific result actually has data for — one card per swipeable page.
    /// Most game types only ever get `[.scoreSnapshot]` (a single, non-swiping page); the Daily
    /// Question is the one case with several, including the isolated-component `.speechBubble`
    /// sticker (see `GameResultShareData.availableLayouts`).
    private var layouts: [GameResultShareLayout] { data.availableLayouts }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                TabView(selection: $page) {
                    ForEach(Array(layouts.enumerated()), id: \.offset) { index, layout in
                        ScrollView {
                            GameResultsShareCard(data: data, layout: layout)
                                .padding(.top, Theme.Spacing.lg)
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if layouts.count > 1 {
                    dotIndicator
                }

                ctaRow
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Share Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .postHogScreenView("Games: Results Share")
    }

    private var dotIndicator: some View {
        HStack(spacing: 6) {
            ForEach(layouts.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.ink : Theme.subtleInk.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - CTA row

    private var currentLayoutIncludesPartnerAnswer: Bool {
        guard layouts.indices.contains(page) else { return false }
        return layouts[page] != .scoreSnapshot
    }

    @ViewBuilder
    private var ctaRow: some View {
        let image = currentPageImage()
        HStack(spacing: Theme.Spacing.sm) {
            if InstagramStoryShare.isAvailable, let image {
                Button {
                    if currentLayoutIncludesPartnerAnswer {
                        pendingShareAction = .instagram(image)
                    } else {
                        InstagramStoryShare.shareSticker(image)
                    }
                } label: {
                    Label("Instagram Stories", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F58529"), Color(hex: "DD2A7B"), Color(hex: "8134AF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
            }
            if let image {
                if currentLayoutIncludesPartnerAnswer {
                    Button {
                        pendingShareAction = .other(image)
                    } label: {
                        otherButtonLabel
                    }
                } else {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("\(data.title) results", image: Image(uiImage: image))) {
                        otherButtonLabel
                    }
                }
            }
        }
        .confirmationDialog(
            "This includes \(data.partner.name)'s answer too — share anyway?",
            isPresented: Binding(
                get: { pendingShareAction != nil },
                set: { isPresented in if !isPresented { pendingShareAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            switch pendingShareAction {
            case .instagram(let image):
                Button("Share to Instagram Stories") { InstagramStoryShare.shareSticker(image) }
            case .other(let image):
                ShareLink(item: Image(uiImage: image), preview: SharePreview("\(data.title) results", image: Image(uiImage: image))) {
                    Text("Share")
                }
            case nil:
                EmptyView()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var otherButtonLabel: some View {
        Text("Other")
            .font(.headline)
            .frame(maxWidth: InstagramStoryShare.isAvailable ? nil : .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 14)
            .background(Theme.cardBackground, in: Capsule())
            .foregroundStyle(Theme.ink)
    }

    private func currentPageImage() -> UIImage? {
        guard layouts.indices.contains(page) else { return nil }
        return renderImage(GameResultsShareCard(data: data, layout: layouts[page]))
    }

    @MainActor
    private func renderImage<V: View>(_ view: V) -> UIImage? {
        // Fixed width regardless of the device's actual screen width — the on-screen preview is
        // responsive, but the exported PNG should always come out the same deliberate size.
        let renderer = ImageRenderer(content: view.frame(width: 360))
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

#Preview {
    let data = GameResultShareData(
        gameType: .deepConversations,
        title: "Daily Question",
        isDaily: true,
        me: MockData.dara,
        partner: MockData.rosa,
        matchPercent: nil,
        triviaMyScore: nil,
        triviaPartnerScore: nil,
        triviaTotalRounds: nil,
        deepConversationSummary: nil,
        singleRoundQuestion: "What's one small thing I did recently that made you feel loved?",
        myAnswer: "Making coffee for me before I even asked.",
        partnerAnswer: "Texting me a photo of the sunset on your walk.",
        dailyStreak: 12
    )
    return GameResultsShareView(data: data)
}
