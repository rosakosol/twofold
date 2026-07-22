//
//  PassportShareView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct PassportShareView: View {
    let couple: Couple
    let person: Person
    let stats: FlightStats
    let visitedCountryNames: Set<String>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            ScrollView {
                PassportShareCard(couple: couple, person: person, stats: stats, visitedCountryNames: visitedCountryNames)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("My Twofold Passport", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .postHogScreenView("Passport: Share")
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(
            content: PassportShareCard(couple: couple, person: person, stats: stats, visitedCountryNames: visitedCountryNames)
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    PassportShareView(
        couple: MockData.couple,
        person: MockData.dara,
        stats: FlightStats(trips: MockData.trips, couple: MockData.couple),
        visitedCountryNames: WorldMap.visitedNames(from: ["Australia", "Singapore", "United Kingdom"])
    )
}
