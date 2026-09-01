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
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    card
                        .padding(.top, Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
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
        let renderer = ImageRenderer(content: view.frame(width: 340))
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
