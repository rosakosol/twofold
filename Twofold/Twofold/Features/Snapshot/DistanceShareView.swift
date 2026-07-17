//
//  DistanceShareView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct DistanceShareView: View {
    let couple: Couple
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?
    @State private var selectedTheme: DistanceShareTheme = .classic

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    DistanceShareCard(couple: couple, myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm, theme: selectedTheme, mapSnapshot: mapSnapshot)
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

                themePicker
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Distance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if mapSnapshot != nil {
                        ShareLink(
                            item: renderCardImage(),
                            preview: SharePreview("The distance between us", image: renderCardImage())
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .task {
                guard mapSnapshot == nil else { return }
                mapSnapshot = await Self.loadMapSnapshot(from: myCity.coordinate, to: partnerCity.coordinate)
            }
        }
    }

    private var themePicker: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(DistanceShareTheme.allCases) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: theme.icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selectedTheme == theme ? Theme.skyBlue : Theme.cardBackground, in: Circle())
                            .foregroundStyle(selectedTheme == theme ? .white : Theme.ink)
                        Text(theme.rawValue).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A real Apple Maps snapshot framed to the great-circle path's own bounding box (sampled
    /// the same way `DistanceShareCard` draws the curve), not just the two raw endpoints — a
    /// route whose arc bulges well north or south of a straight line between its endpoints (any
    /// long east-west route) needs that peak included in the frame too, or the drawn path runs
    /// off the edge of the image.
    private static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> MKMapSnapshotter.Snapshot? {
        let sampleCount = 20
        var longitudes = (0...sampleCount).map { i in
            Geo.intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)).longitude
        }
        let latitudes = (0...sampleCount).map { i in
            Geo.intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)).latitude
        }
        // Antimeridian-safe bounding box: if the raw longitudes span more than half the globe,
        // they almost certainly wrapped around ±180° rather than the route genuinely being that
        // wide — shift the negative side by a full turn before taking min/max, then unwrap the
        // result back into range.
        if let first = longitudes.first, longitudes.contains(where: { abs($0 - first) > 180 }) {
            longitudes = longitudes.map { $0 < 0 ? $0 + 360 : $0 }
        }

        let minLat = latitudes.min() ?? a.latitude, maxLat = latitudes.max() ?? a.latitude
        let minLon = longitudes.min() ?? a.longitude, maxLon = longitudes.max() ?? a.longitude
        let rawLatSpan = maxLat - minLat
        let rawLonSpan = maxLon - minLon

        let padding = 1.6
        let minDelta = 14.0
        let maxDelta = 160.0
        let latSpan = min(maxDelta, max(minDelta, rawLatSpan * padding))
        let lonSpan = min(maxDelta, max(minDelta, rawLonSpan * padding))

        // A snapshot's Apple Maps attribution is always anchored to its bottom-left corner, so
        // the southmost point needs a bit of extra clearance below it — the bottom edge sits at
        // `center - span/2`, so *lowering* center latitude moves that edge further south, away
        // from that point. This is a fixed fraction of the *final, padded* span, not of the
        // padding room itself — an earlier version scaled with the padding room, which is
        // proportional to the route's raw span, so a long route (lots of padding room) got a
        // wildly oversized shift that pushed the point out toward the opposite edge instead.
        //
        // Longitude is left uncentered (no matching leftward bias) — the attribution is a
        // small, short strip along the very bottom edge, not really a left/right concern, and
        // adding a horizontal bias on top of the vertical one consistently left one pin visibly
        // closer to its edge than the other, which read as off-center rather than helpful.
        let latBiasFraction = 0.09
        var centerLongitude = (minLon + maxLon) / 2
        if centerLongitude > 180 { centerLongitude -= 360 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2 - latSpan * latBiasFraction, longitude: centerLongitude)

        let options = MKMapSnapshotter.Options()
        // `.standard` (Apple's ordinary bright colored map — green land, blue water), not
        // `.hybrid` — the satellite imagery `.hybrid` layers underneath reads as dark and dull
        // next to the rest of the app's maps, which are all this same bright standard style
        // (`FlightMapView` never sets `mapType` at all, so it renders with this same default).
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        options.size = DistanceShareCard.mapSize
        options.showsBuildings = false

        do {
            return try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
    }

    @MainActor
    private func renderCardImage() -> Image {
        // Fixed width regardless of the device's actual screen width — the on-screen preview is
        // responsive, but the exported PNG should always come out the same deliberate size.
        let renderer = ImageRenderer(
            content: DistanceShareCard(couple: couple, myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm, theme: selectedTheme, mapSnapshot: mapSnapshot)
                .frame(width: 360)
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    DistanceShareView(
        couple: MockData.couple,
        myCity: MockData.dara.homeCity ?? MockData.singapore,
        partnerCity: MockData.rosa.homeCity ?? MockData.melbourne,
        distanceKm: 6300
    )
}
