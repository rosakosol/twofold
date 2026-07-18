//
//  SnapshotShareView.swift
//  Twofold
//

import SwiftUI
import MapKit
import PostHog

struct SnapshotShareView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedTheme: SnapshotTheme = .classic
    @State private var renderedImage: Image?
    /// Real satellite Earth imagery for the `.earth` theme — generated once here (rather than
    /// inside `SnapshotThemeCard` itself) so it's already loaded by the time `renderCardImage`
    /// needs it synchronously for the share sheet, not still mid-flight.
    @State private var earthGlobeImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    SnapshotThemeCard(couple: appModel.couple, trips: appModel.trips, stats: appModel.stats, theme: selectedTheme, earthGlobeImage: earthGlobeImage)
                        .padding(.top, Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                }
                .padding(.horizontal, Theme.Spacing.md)

                themePicker
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Snapshot")
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
                guard earthGlobeImage == nil else { return }
                earthGlobeImage = await Self.loadEarthGlobeImage()
            }
        }
        .postHogScreenView("Snapshot: Share")
    }

    /// A wide-angle satellite snapshot centered on the Atlantic so both hemispheres show some
    /// land — `MKMapSnapshotter` renders headlessly (unlike a live `Map`), so the result is a
    /// plain `UIImage` that's safe to embed in an offscreen `ImageRenderer` export.
    private static func loadEarthGlobeImage() async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.mapType = .satellite
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: -30),
            span: MKCoordinateSpan(latitudeDelta: 170, longitudeDelta: 170)
        )
        options.size = CGSize(width: 500, height: 700)
        options.showsBuildings = false
        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
            return snapshot.image
        } catch {
            return nil
        }
    }

    private var themePicker: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(SnapshotTheme.allCases) { theme in
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

    @MainActor
    private func renderCardImage() -> Image {
        // Fixed width regardless of the device's actual screen width — the on-screen preview
        // is responsive (`SnapshotThemeCard` fills whatever it's given), but the exported PNG
        // should always come out the same deliberate size.
        let renderer = ImageRenderer(
            content: SnapshotThemeCard(couple: appModel.couple, trips: appModel.trips, stats: appModel.stats, theme: selectedTheme, earthGlobeImage: earthGlobeImage)
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
    SnapshotShareView()
        .environment(AppModel())
}
