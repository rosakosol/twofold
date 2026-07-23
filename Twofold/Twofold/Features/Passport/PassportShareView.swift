//
//  PassportShareView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct PassportShareView: View {
    let stats: FlightStats

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            ScrollView {
                PassportShareCard(stats: stats)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                    .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Flight Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("My Flight Stats", image: renderCardImage())
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
        let renderer = ImageRenderer(content: PassportShareCard(stats: stats))
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    PassportShareView(stats: FlightStats(trips: MockData.trips, couple: MockData.couple))
}
