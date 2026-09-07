//
//  DistanceRevealShareView.swift
//  Twofold
//
//  The distance-reveal moment's share screen — one card (`DistanceSnapshotCard`, mirroring the
//  live reveal screen itself) and a single share button. No partner-consent gating like
//  `GameResultsShareView` needs for answer text — everything here (distance, cities, photos) is
//  this user's own onboarding input, never anyone else's words.
//

import PostHog
import SwiftUI
import MapKit

struct DistanceRevealShareView: View {
    let distanceKm: Double
    let comparison: String
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    let hoursApart: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?
    /// The card's own laid-out height at its design width. Measured rather than assumed: it varies
    /// with whether there's a timezone difference to show and how long the comparison line runs.
    @State private var cardHeight: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                // Scaled to fit rather than scrolled. This is the one thing on the screen and it
                // should be seeable in one look — a share preview you have to scroll to judge isn't
                // really a preview. The card keeps its design size for the exported image; only
                // what's on screen is shrunk, and only when it has to be.
                GeometryReader { proxy in
                    let scale = fittingScale(in: proxy.size)
                    card
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                        .scaleEffect(scale, anchor: .center)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .padding(.horizontal, Theme.Spacing.md)

                ctaRow
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            }
            .padding(.top, Theme.Spacing.md)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
            .task {
                guard mapSnapshot == nil else { return }
                mapSnapshot = await DistanceMapView.loadMapSnapshot(from: myCity.coordinate, to: partnerCity.coordinate, distanceKm: distanceKm)
            }
        }
        .postHogScreenView("Onboarding: Distance Reveal Share")
    }

    /// How much the card has to shrink to sit inside the space available, never growing past its
    /// natural size — a card that fits already is left alone rather than blown up.
    ///
    /// `scaleEffect` doesn't change the layout size the measurement above reports, so scaling can't
    /// feed back into the number it was computed from.
    private func fittingScale(in available: CGSize) -> CGFloat {
        Self.fittingScale(cardHeight: cardHeight, in: available)
    }

    static func fittingScale(cardHeight: CGFloat, in available: CGSize) -> CGFloat {
        guard cardHeight > 0, available.height > 0, available.width > 0 else { return 1 }
        return min(1, min(available.height / cardHeight, available.width / cardWidth))
    }

    /// The width the card is designed at, and the width it exports at.
    static let cardWidth: CGFloat = 340

    private var card: some View {
        DistanceSnapshotCard(
            distanceKm: distanceKm,
            comparison: comparison,
            myCity: myCity,
            partnerCity: partnerCity,
            selfPhoto: selfPhoto,
            partnerPhoto: partnerPhoto,
            hoursApart: hoursApart,
            mapSnapshot: mapSnapshot
        )
    }

    // MARK: - CTA row

    @ViewBuilder
    private var ctaRow: some View {
        if let image = mapSnapshot != nil ? renderImage(card) : nil {
            ShareLink(item: Image(uiImage: image), preview: SharePreview("The distance between us", image: Image(uiImage: image))) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    @MainActor
    private func renderImage<V: View>(_ view: V) -> UIImage? {
        // Fixed width regardless of the device's actual screen width — the on-screen preview is
        // responsive, but the exported PNG should always come out the same deliberate size.
        // Matches `DistanceSnapshotCard`'s own outer frame width.
        // Handed the scheme explicitly for the same reason as the other share screens — see
        // GameResultsShareView's note.
        let renderer = ImageRenderer(content: view.frame(width: Self.cardWidth).environment(\.colorScheme, colorScheme))
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

#Preview {
    DistanceRevealShareView(
        distanceKm: 16_902,
        comparison: DistanceSnapshotCard.comparison(for: 16_902),
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "London" }!,
        selfPhoto: nil,
        partnerPhoto: nil,
        hoursApart: 9
    )
}
