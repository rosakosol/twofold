//
//  RelationshipStatsShareView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct RelationshipStatsShareView: View {
    let couple: Couple
    let stats: RelationshipMilestoneStats

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var appearance: ColorScheme?

    private var resolvedAppearance: ColorScheme { appearance ?? systemColorScheme }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    card
                        .padding(Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

                ShareCardAppearancePicker(selection: Binding(get: { resolvedAppearance }, set: { appearance = $0 }))
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Relationship Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("Relationship stats", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .postHogScreenView("Passport: Share Our Story")
    }

    private var card: some View {
        RelationshipStatsShareCard(couple: couple, stats: stats)
            .environment(\.colorScheme, resolvedAppearance)
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    RelationshipStatsShareView(
        couple: MockData.couple,
        stats: RelationshipMilestoneStats(couple: MockData.couple, trips: MockData.trips, memories: MockData.memories)
    )
}
