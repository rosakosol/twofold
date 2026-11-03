//
//  StatShareView.swift
//  Twofold
//
//  The full-screen preview for sharing one Full Flight Stats or Full Trip Stats card.
//

import PostHog
import SwiftUI

/// Everything `StatShareView` needs to re-render one full-stats section standalone — captured once
/// when its share button is tapped, since `rows` closures only read already-available stats/scope
/// state, not anything that changes while the sheet is open. Shared with `FullTripStatsView`.
struct StatCardSpec: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let unit: String?
    let rows: AnyView
}

/// The full-screen "see it before you send it" preview for one Full Flight Stats card — same
/// flow `PassportShareView` already gives the summary Flight Stats card (card preview, Close,
/// and a `ShareLink` in the toolbar), just for a single section's card instead of the whole thing.
struct StatShareView: View {
    let stat: StatCardSpec

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var appearance: ColorScheme?

    private var resolvedAppearance: ColorScheme { appearance ?? systemColorScheme }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    cardView
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

                ShareCardAppearancePicker(selection: Binding(get: { resolvedAppearance }, set: { appearance = $0 }))
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(ScreenBackground())
            .navigationTitle(stat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview(stat.title, image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .postHogScreenView("Passport: Stat Share")
    }

    /// Same card format `PassportShareCard` uses for the summary Flight Stats card (brand mark up
    /// top, the card in `FlightStatsCard`'s own `SectionCard` chrome underneath, same corner
    /// radius/width) so this reads as a smaller sibling of that same share image.
    private var cardView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.textPrimary, size: 24, textStyle: .title3)

            SectionCard {
                StatCardHeader(icon: stat.icon, title: stat.title, value: stat.value, unit: stat.unit)
                stat.rows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 360)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, resolvedAppearance)
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}
