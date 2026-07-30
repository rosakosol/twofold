//
//  TripStatsShareView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct TripStatsShareView: View {
    let stats: TripStats

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
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

                ShareCardAppearancePicker(selection: Binding(get: { resolvedAppearance }, set: { appearance = $0 }))
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Trip Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("My Trip Stats", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .postHogScreenView("Passport: Share Trip Stats")
    }

    private var card: some View {
        TripStatsShareCard(stats: stats)
            .environment(\.colorScheme, resolvedAppearance)
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    TripStatsShareView(stats: TripStats(trips: MockData.trips))
}
