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
                mapSnapshot = await Self.loadMapSnapshot(from: myCity.coordinate, to: partnerCity.coordinate, distanceKm: distanceKm)
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

    /// A real globe snapshot (`.hybrid(elevation: .realistic)`, the same configuration
    /// `RelationshipGlobeView`'s live `Map` uses) — centered and sized differently depending on
    /// whether both cities fit one cropped view (`DistanceShareCard.isOffGlobe`): close enough,
    /// centered on your spherical midpoint at the larger `normalGlobeSize`; far enough apart that
    /// they can't both land in frame, centered on just your own city at the smaller,
    /// left-biased `offGlobeSize` `DistanceShareCard.offGlobeContent(_:)` expects.
    private static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, distanceKm: Double) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
        options.showsBuildings = false

        if distanceKm > DistanceShareCard.offGlobeThresholdKm {
            options.region = MKCoordinateRegion(center: a, span: MKCoordinateSpan(latitudeDelta: 70, longitudeDelta: 70))
            options.size = CGSize(width: DistanceShareCard.offGlobeSize, height: DistanceShareCard.offGlobeSize)
        } else {
            options.region = MKCoordinateRegion(
                center: Geo.sphericalMidpoint(a, b),
                span: MKCoordinateSpan(latitudeDelta: 110, longitudeDelta: 110)
            )
            options.size = CGSize(width: DistanceShareCard.normalGlobeSize, height: DistanceShareCard.normalGlobeSize)
        }

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
