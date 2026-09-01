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
    @State private var activeTab: Tab = .result
    /// Which entry in `data.deepConversationRounds` is currently featured on the share cards —
    /// single selection only (picking a new topic on the Questions & Answers tab just replaces
    /// this, it never adds to a set). Irrelevant for every other game type/the Daily Question,
    /// which already have exactly one Q&A and no picker.
    @State private var selectedRoundIndex = 0
    /// Set instead of sharing directly whenever the current layout renders the *partner's*
    /// answer text (every layout except `.scoreSnapshot` — see `GameResultShareData.availableLayouts`,
    /// only reachable when there's a real single-round Q&A to render). Mutual in-app reveal
    /// isn't the same as consent to have a partner's own words exported to Photos/Messages/
    /// Instagram, so this gates both CTAs behind a one-time-per-tap confirmation instead of
    /// sharing on the first tap the way `.scoreSnapshot` (no free text, no one else's words) can.
    /// One per button, rather than one shared value for both.
    ///
    /// A `confirmationDialog` anchors to the view it's attached to, and a single dialog can only
    /// be attached to their common parent — the row — so it pointed at the gap between the two
    /// buttons, reading as though it belonged to Instagram Stories no matter which one was tapped.
    /// Each button now carries its own.
    @State private var pendingInstagramShare: UIImage?
    @State private var pendingOtherShare: UIImage?

    private enum Tab: Hashable { case result, questions }

    /// Only Deep Conversations decks with more than one topic have anything to pick between — the
    /// Daily Question and every other game type render straight from `data`'s own single-round
    /// fields, so the segmented tab bar/second tab would just be an empty picker for them.
    private var hasTopicPicker: Bool {
        data.deepConversationRounds?.isEmpty == false
    }

    /// `data` with `singleRoundQuestion`/`myAnswer`/`partnerAnswer` overwritten from whichever
    /// topic is selected, when there's a picker to begin with — every other field (and every other
    /// game type/the Daily Question, where `deepConversationRounds` is nil) passes through
    /// unchanged, since `.scoreSnapshot` never reads those three fields anyway.
    private var effectiveData: GameResultShareData {
        guard let rounds = data.deepConversationRounds, rounds.indices.contains(selectedRoundIndex) else { return data }
        var copy = data
        let round = rounds[selectedRoundIndex]
        copy.singleRoundQuestion = round.question
        copy.myAnswer = round.myAnswer
        copy.partnerAnswer = round.partnerAnswer
        return copy
    }

    private var layouts: [GameResultShareLayout] { effectiveData.availableLayouts }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasTopicPicker {
                    Picker("View", selection: $activeTab) {
                        Text("Share Result").tag(Tab.result)
                        Text("Questions & Answers").tag(Tab.questions)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.sm)
                }

                switch activeTab {
                case .result:
                    resultTab
                case .questions:
                    questionsTab
                }
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

    // MARK: - Share Result tab

    private var resultTab: some View {
        VStack(spacing: Theme.Spacing.md) {
            TabView(selection: $page) {
                ForEach(Array(layouts.enumerated()), id: \.offset) { index, layout in
                    ScrollView {
                        GameResultsShareCard(data: effectiveData, layout: layout)
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
        .padding(.top, Theme.Spacing.md)
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

    // MARK: - Questions & Answers tab

    /// Full question text and both full answers, unlike the small share cards which are laid out
    /// for a square-ish sticker and can't afford to show everything at length. Tapping a row here
    /// just changes `selectedRoundIndex` — switching back to the Share Result tab (or the dot
    /// indicator there) already reflects it, no extra state to sync.
    private var questionsTab: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(Array((data.deepConversationRounds ?? []).enumerated()), id: \.offset) { index, round in
                    Button {
                        selectedRoundIndex = index
                    } label: {
                        questionRow(round, isSelected: index == selectedRoundIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    private func questionRow(_ round: GameResultShareRound, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(round.question)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
            }
            answerLine(name: data.me.name, text: round.myAnswer)
            answerLine(name: data.partner.name, text: round.partnerAnswer)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? Theme.skyBlue.opacity(0.08) : Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(isSelected ? Theme.skyBlue : Color.clear, lineWidth: 1.5)
        )
    }

    private func answerLine(name: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
            Text(text.isEmpty ? "Skipped this one" : text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
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
                        pendingInstagramShare = image
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
                .confirmationDialog(
                    partnerAnswerWarning,
                    isPresented: presenting($pendingInstagramShare),
                    titleVisibility: .visible
                ) {
                    if let pendingInstagramShare {
                        Button("Share to Instagram Stories") { InstagramStoryShare.shareSticker(pendingInstagramShare) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
            if let image {
                if currentLayoutIncludesPartnerAnswer {
                    Button {
                        pendingOtherShare = image
                    } label: {
                        otherButtonLabel
                    }
                    .confirmationDialog(
                        partnerAnswerWarning,
                        isPresented: presenting($pendingOtherShare),
                        titleVisibility: .visible
                    ) {
                        if let pendingOtherShare {
                            ShareLink(
                                item: Image(uiImage: pendingOtherShare),
                                preview: SharePreview("\(data.title) results", image: Image(uiImage: pendingOtherShare))
                            ) {
                                Text("Share")
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                } else {
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("\(data.title) results", image: Image(uiImage: image))) {
                        otherButtonLabel
                    }
                }
            }
        }
    }

    private var partnerAnswerWarning: String {
        "This includes \(data.partner.name)'s answer too — share anyway?"
    }

    /// A `Bool` binding that clears the held image when the dialog dismisses.
    private func presenting(_ image: Binding<UIImage?>) -> Binding<Bool> {
        Binding(get: { image.wrappedValue != nil }, set: { if !$0 { image.wrappedValue = nil } })
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
        return renderImage(GameResultsShareCard(data: effectiveData, layout: layouts[page]))
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
