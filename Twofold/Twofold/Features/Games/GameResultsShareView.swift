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
    /// Which entries in `data.deepConversationRounds` are included as swipeable pages — starts
    /// with every topic selected (matches the old "share everything available" behavior), and is
    /// toggled per-topic via the toolbar's "Choose Topics" menu. Irrelevant (and left empty) for
    /// every other game type/the Daily Question, which already have exactly one Q&A and no picker.
    @State private var selectedRoundIDs: Set<UUID>
    /// Set instead of sharing directly whenever the current layout renders the *partner's*
    /// answer text (every layout except `.scoreSnapshot` — see `GameResultShareData.availableLayouts`,
    /// only reachable when there's a real single-round Q&A to render). Mutual in-app reveal
    /// isn't the same as consent to have a partner's own words exported to Photos/Messages/
    /// Instagram, so this gates both CTAs behind a one-time-per-tap confirmation instead of
    /// sharing on the first tap the way `.scoreSnapshot` (no free text, no one else's words) can.
    @State private var pendingShareAction: PendingShareAction?

    init(data: GameResultShareData) {
        self.data = data
        _selectedRoundIDs = State(initialValue: Set((data.deepConversationRounds ?? []).map(\.id)))
    }

    private enum PendingShareAction {
        case instagram(UIImage)
        case other(UIImage)
    }

    /// One swipeable page — `round` is nil for every non-deepConversations game type and the
    /// Daily Question, which render straight from `data`'s own single-round fields; a multi-round
    /// Deep Conversations deck instead produces one of these per *selected* topic per layout, so
    /// `round` carries which topic's Q&A this specific page should overlay onto `data`.
    private struct SharePage {
        let round: GameResultShareRound?
        let layout: GameResultShareLayout
    }

    /// Every page to actually render. A multi-round Deep Conversations deck gets both Q&A layouts
    /// (`.namesAndAnswer`, `.speechBubble`) for each topic the person has checked in the "Choose
    /// Topics" menu — deselecting every topic isn't possible (see `toggleRound`), so this is never
    /// empty once there are any rounds to begin with. Every other case (including the Daily
    /// Question) just renders `data.availableLayouts` as-is, since those already carry at most one
    /// Q&A pair with nothing to pick between.
    private var pages: [SharePage] {
        if let rounds = data.deepConversationRounds, !rounds.isEmpty {
            let selected = rounds.filter { selectedRoundIDs.contains($0.id) }
            return selected.flatMap { round in
                [SharePage(round: round, layout: .namesAndAnswer), SharePage(round: round, layout: .speechBubble)]
            }
        }
        return data.availableLayouts.map { SharePage(round: nil, layout: $0) }
    }

    /// `data` with `singleRoundQuestion`/`myAnswer`/`partnerAnswer` overwritten from this page's
    /// own topic, when it has one — every other field (and every other game type/the Daily
    /// Question, where `page.round` is always nil) passes through unchanged.
    private func shareData(for page: SharePage) -> GameResultShareData {
        guard let round = page.round else { return data }
        var copy = data
        copy.singleRoundQuestion = round.question
        copy.myAnswer = round.myAnswer
        copy.partnerAnswer = round.partnerAnswer
        return copy
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, sharePage in
                        ScrollView {
                            GameResultsShareCard(data: shareData(for: sharePage), layout: sharePage.layout)
                                .padding(.top, Theme.Spacing.lg)
                                .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                if pages.count > 1 {
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
                if let rounds = data.deepConversationRounds, !rounds.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        topicsMenu(rounds)
                    }
                }
            }
        }
        .postHogScreenView("Games: Results Share")
    }

    /// Checking/unchecking a topic here is about which exchanges to include, never about
    /// "matching" — free-text Deep Conversations answers have no equivalent to This-or-That/
    /// More-Likely's similarity percent (see `GameResultShareData.deepConversationRounds`'s own
    /// doc comment).
    private func topicsMenu(_ rounds: [GameResultShareRound]) -> some View {
        Menu {
            ForEach(rounds) { round in
                Button {
                    toggleRound(round.id)
                } label: {
                    if selectedRoundIDs.contains(round.id) {
                        Label(round.question, systemImage: "checkmark")
                    } else {
                        Text(round.question)
                    }
                }
            }
        } label: {
            Label("Choose Topics", systemImage: "list.bullet")
        }
        .labelStyle(.iconOnly)
    }

    /// Always keeps at least one topic selected — an entirely empty selection would leave the
    /// share sheet with no pages and no image for the CTA row to share, a dead end rather than a
    /// useful state. Clamps `page` back onto the last remaining page if the current one was just
    /// removed by deselecting its topic.
    private func toggleRound(_ id: UUID) {
        if selectedRoundIDs.contains(id) {
            guard selectedRoundIDs.count > 1 else { return }
            selectedRoundIDs.remove(id)
        } else {
            selectedRoundIDs.insert(id)
        }
        if !pages.indices.contains(page) {
            page = max(0, pages.count - 1)
        }
    }

    private var dotIndicator: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.ink : Theme.subtleInk.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - CTA row

    private var currentLayoutIncludesPartnerAnswer: Bool {
        guard pages.indices.contains(page) else { return false }
        return pages[page].layout != .scoreSnapshot
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
        guard pages.indices.contains(page) else { return nil }
        let currentPage = pages[page]
        return renderImage(GameResultsShareCard(data: shareData(for: currentPage), layout: currentPage.layout))
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

#Preview("Daily Question") {
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
        deepConversationRounds: nil,
        singleRoundQuestion: "What's one small thing I did recently that made you feel loved?",
        myAnswer: "Making coffee for me before I even asked.",
        partnerAnswer: "Texting me a photo of the sunset on your walk.",
        dailyStreak: 12
    )
    return GameResultsShareView(data: data)
}

#Preview("Deep Conversations deck") {
    let data = GameResultShareData(
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
            GameResultShareRound(question: "What's one small thing I did recently that made you feel loved?", myAnswer: "Making coffee for me before I even asked.", partnerAnswer: "Texting me a photo of the sunset on your walk."),
            GameResultShareRound(question: "What does your ideal weekend look like?", myAnswer: "Sleeping in, then a long walk somewhere new.", partnerAnswer: "Cooking a big breakfast together."),
        ],
        singleRoundQuestion: nil,
        myAnswer: nil,
        partnerAnswer: nil,
        dailyStreak: nil
    )
    return GameResultsShareView(data: data)
}
