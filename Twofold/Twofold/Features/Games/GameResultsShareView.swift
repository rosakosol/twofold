//
//  GameResultsShareView.swift
//  Twofold
//

import SwiftUI

struct GameResultsShareView: View {
    let data: GameResultShareData

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedLayout: GameResultShareLayout

    init(data: GameResultShareData) {
        self.data = data
        _selectedLayout = State(initialValue: data.availableLayouts.first ?? .scoreSnapshot)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    GameResultsShareCard(data: data, layout: selectedLayout)
                        .padding(.top, Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                }
                .padding(.horizontal, Theme.Spacing.md)

                if data.availableLayouts.count > 1 {
                    layoutPicker
                        .padding(.bottom, Theme.Spacing.md)
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
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("\(data.title) results", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var layoutPicker: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(data.availableLayouts) { layout in
                Button {
                    selectedLayout = layout
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: layout.icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selectedLayout == layout ? Theme.skyBlue : Theme.cardBackground, in: Circle())
                            .foregroundStyle(selectedLayout == layout ? .white : Theme.ink)
                        Text(layout.label).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func renderCardImage() -> Image {
        // Fixed width regardless of the device's actual screen width — the on-screen preview is
        // responsive, but the exported PNG should always come out the same deliberate size.
        let renderer = ImageRenderer(content: GameResultsShareCard(data: data, layout: selectedLayout).frame(width: 360))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
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
