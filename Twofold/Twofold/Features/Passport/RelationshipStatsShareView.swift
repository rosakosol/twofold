//
//  RelationshipStatsShareView.swift
//  Twofold
//

import SwiftUI

struct RelationshipStatsShareView: View {
    let couple: Couple
    let trips: [Trip]
    let memories: [Memory]
    let stats: RelationshipMilestoneStats

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedMemoryIDs: Set<Memory.ID> = []
    @State private var showingPhotoPicker = false
    @State private var showingCustomization = false
    @State private var backgroundTheme: RelationshipStatsCardBackground = .auto
    @State private var showTripsChip = true
    @State private var showReunionsChip = true
    @State private var showMemoriesChip = true

    /// Every memory that could possibly show in the grid — the picker's own list, and the pool
    /// `defaultSelection()` draws its random pick from.
    private var photoEligibleMemories: [Memory] {
        memories.filter { $0.photoURL != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                card
                    .padding(Theme.Spacing.lg)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Our Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Customize", systemImage: "paintbrush") {
                            showingCustomization = true
                        }
                        .labelStyle(.iconOnly)

                        if !photoEligibleMemories.isEmpty {
                            Button("Choose Photos", systemImage: "photo.on.rectangle") {
                                showingPhotoPicker = true
                            }
                            .labelStyle(.iconOnly)
                        }
                        ShareLink(
                            item: renderCardImage(),
                            preview: SharePreview("Our story so far", image: renderCardImage())
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingPhotoPicker) {
                RelationshipStatsPhotoPickerView(memories: photoEligibleMemories, selectedIDs: $selectedMemoryIDs)
            }
            .sheet(isPresented: $showingCustomization) {
                RelationshipStatsCustomizationView(
                    backgroundTheme: $backgroundTheme,
                    showTripsChip: $showTripsChip,
                    showReunionsChip: $showReunionsChip,
                    showMemoriesChip: $showMemoriesChip
                )
            }
            .onAppear {
                guard selectedMemoryIDs.isEmpty else { return }
                selectedMemoryIDs = Self.defaultSelection(from: photoEligibleMemories)
            }
        }
    }

    private var card: some View {
        RelationshipStatsShareCard(
            couple: couple,
            trips: trips,
            memories: memories,
            selectedMemoryIDs: selectedMemoryIDs,
            stats: stats,
            backgroundTheme: backgroundTheme,
            showTripsChip: showTripsChip,
            showReunionsChip: showReunionsChip,
            showMemoriesChip: showMemoriesChip
        )
    }

    /// A random default pick, capped at `RelationshipStatsShareCard.maxStoryPhotos` — random
    /// rather than "most recent," so the same couple's card looks a little different each time
    /// they generate one, and re-picking is as simple as reopening this screen. Overridable at
    /// any time via "Choose Photos."
    private static func defaultSelection(from eligible: [Memory]) -> Set<Memory.ID> {
        Set(eligible.shuffled().prefix(RelationshipStatsShareCard.maxStoryPhotos).map(\.id))
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
        trips: MockData.trips,
        memories: MockData.memories,
        stats: RelationshipMilestoneStats(trips: MockData.trips, memories: MockData.memories, startedDatingOn: .now.addingTimeInterval(-86_400 * 400))
    )
}
