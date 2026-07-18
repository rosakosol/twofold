//
//  RelationshipStatsShareView.swift
//  Twofold
//

import MapKit
import SwiftUI

struct RelationshipStatsShareView: View {
    let couple: Couple
    let trips: [Trip]
    let memories: [Memory]
    let stats: RelationshipMilestoneStats

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?

    /// The same photo+place filter `RelationshipStatsShareCard.mappableMemories` applies —
    /// duplicated rather than shared since this side only needs the coordinates, to fit the
    /// snapshot's region around them.
    private var mappableMemoryCoordinates: [CLLocationCoordinate2D] {
        memories
            .filter { $0.photoURL != nil && $0.place != nil }
            .sorted { $0.date > $1.date }
            .prefix(3)
            .compactMap { $0.place?.coordinate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                RelationshipStatsShareCard(couple: couple, trips: trips, memories: memories, stats: stats, mapSnapshot: mapSnapshot)
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
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("Our story so far", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .task {
                guard mapSnapshot == nil,
                      let userCoordinate = couple.partnerA.homeCity?.coordinate,
                      let partnerCoordinate = couple.partnerB.homeCity?.coordinate else { return }
                mapSnapshot = await Self.loadMapSnapshot(userCoordinate: userCoordinate, partnerCoordinate: partnerCoordinate, memoryCoordinates: mappableMemoryCoordinates)
            }
        }
    }

    /// A real Apple Maps snapshot framed to fit both home cities' great-circle path (sampled the
    /// same way `DistanceShareCard` draws the curve — a straight endpoint-to-endpoint bounding
    /// box would clip a route that bulges north/south of a straight line) *and* every mappable
    /// memory location, so no marker this card draws ever lands outside the visible frame.
    private static func loadMapSnapshot(userCoordinate: CLLocationCoordinate2D, partnerCoordinate: CLLocationCoordinate2D, memoryCoordinates: [CLLocationCoordinate2D]) async -> MKMapSnapshotter.Snapshot? {
        let routeSampleCount = 20
        var points = (0...routeSampleCount).map { i in
            Geo.intermediateGreatCirclePoint(userCoordinate, partnerCoordinate, fraction: Double(i) / Double(routeSampleCount))
        }
        points += memoryCoordinates

        var longitudes = points.map(\.longitude)
        let latitudes = points.map(\.latitude)
        // Antimeridian-safe bounding box — see `DistanceShareView.loadMapSnapshot`'s comment.
        if let first = longitudes.first, longitudes.contains(where: { abs($0 - first) > 180 }) {
            longitudes = longitudes.map { $0 < 0 ? $0 + 360 : $0 }
        }

        let minLat = latitudes.min() ?? userCoordinate.latitude, maxLat = latitudes.max() ?? userCoordinate.latitude
        let minLon = longitudes.min() ?? userCoordinate.longitude, maxLon = longitudes.max() ?? userCoordinate.longitude

        let padding = 1.5
        let minDelta = 12.0
        let maxDelta = 160.0
        let latSpan = min(maxDelta, max(minDelta, (maxLat - minLat) * padding))
        let lonSpan = min(maxDelta, max(minDelta, (maxLon - minLon) * padding))

        var centerLongitude = (minLon + maxLon) / 2
        if centerLongitude > 180 { centerLongitude -= 360 }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLongitude)

        let options = MKMapSnapshotter.Options()
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        options.size = RelationshipStatsShareCard.canvasSize
        options.showsBuildings = false
        do {
            return try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(
            content: RelationshipStatsShareCard(couple: couple, trips: trips, memories: memories, stats: stats, mapSnapshot: mapSnapshot)
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
    RelationshipStatsShareView(
        couple: MockData.couple,
        trips: MockData.trips,
        memories: MockData.memories,
        stats: RelationshipMilestoneStats(trips: MockData.trips, memories: MockData.memories, startedDatingOn: .now.addingTimeInterval(-86_400 * 400))
    )
}
