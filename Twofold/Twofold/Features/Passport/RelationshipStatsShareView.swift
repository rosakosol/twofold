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
    @State private var showingCustomization = false
    @State private var showTripsChip = true
    @State private var showReunionsChip = true
    @State private var showMemoriesChip = true

    var body: some View {
        NavigationStack {
            ScrollView {
                card
                    .padding(Theme.Spacing.lg)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
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
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Customize", systemImage: "slider.horizontal.3") {
                            showingCustomization = true
                        }
                        .labelStyle(.iconOnly)

                        ShareLink(
                            item: renderCardImage(),
                            preview: SharePreview("Relationship stats", image: renderCardImage())
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCustomization) {
                RelationshipStatsCustomizationView(
                    showTripsChip: $showTripsChip,
                    showReunionsChip: $showReunionsChip,
                    showMemoriesChip: $showMemoriesChip
                )
            }
        }
        .postHogScreenView("Passport: Share Our Story")
    }

    private var card: some View {
        RelationshipStatsShareCard(
            couple: couple,
            stats: stats,
            showTripsChip: showTripsChip,
            showReunionsChip: showReunionsChip,
            showMemoriesChip: showMemoriesChip
        )
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
