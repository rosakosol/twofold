//
//  DistanceShareView.swift
//  Twofold
//

import SwiftUI
import MapKit
import PostHog

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

                ctaArea
                    .padding(.horizontal, Theme.Spacing.lg)
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
            }
            .task {
                guard mapSnapshot == nil else { return }
                mapSnapshot = await Self.loadMapSnapshot(from: myCity.coordinate, to: partnerCity.coordinate, distanceKm: distanceKm)
            }
        }
        .postHogScreenView("Snapshot: Distance Share")
    }

    // MARK: - CTA row

    /// Bottom-of-panel Instagram Stories/Other row, same placement and styling as
    /// `FlightShareView`'s sticker pages — replaces the old corner toolbar `ShareLink`, which was
    /// this screen's own one-off pattern rather than matching the rest of the app's share flows.
    @ViewBuilder
    private var ctaArea: some View {
        if mapSnapshot != nil {
            ctaRow(image: renderCardImage())
        }
    }

    private func ctaRow(image: UIImage?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if InstagramStoryShare.isAvailable, let image {
                Button {
                    InstagramStoryShare.shareSticker(image)
                } label: {
                    Label("Instagram Stories", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "F58529"), Color(hex: "DD2A7B"), Color(hex: "8134AF")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
            }
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview("The distance between us", image: Image(uiImage: image))) {
                    Text("Other")
                        .font(.headline)
                        .frame(maxWidth: InstagramStoryShare.isAvailable ? nil : .infinity)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, 14)
                        .background(Theme.cardBackground, in: Capsule())
                        .foregroundStyle(Theme.ink)
                }
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
    private func renderCardImage() -> UIImage? {
        // Fixed width regardless of the device's actual screen width — the on-screen preview is
        // responsive, but the exported PNG should always come out the same deliberate size.
        let renderer = ImageRenderer(
            content: DistanceShareCard(couple: couple, myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm, theme: selectedTheme, mapSnapshot: mapSnapshot)
                .frame(width: 360)
        )
        renderer.scale = displayScale
        return renderer.uiImage
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
