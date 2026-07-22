//
//  FlightShareView.swift
//  Twofold
//
//  The flight tracking screen's Share sheet — a swipeable 4-page picker (Plain Text, Route Map,
//  Boarding Pass, Flight Status), replacing the old single `ShareLink(item: shareText)` menu item
//  in `FlightTrackingView`. `TabView(.page)` is new to this app (every other share flow —
//  Distance, Passport, Relationship Stats — presents one card at a time with at most a flat theme
//  picker), introduced here specifically because the reference design swipes between genuinely
//  different card layouts, not just palette variants of one layout.
//

import MapKit
import PostHog
import SwiftUI

struct FlightShareView: View {
    let flight: Flight

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var page = 0
    @State private var stickerStyle: FlightStickerStyle = .light
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?
    @State private var airlineLogo: UIImage?

    private static let pageCount = 4

    private var travelerNames: [String] {
        [appModel.currentUser, appModel.partner].filter { flight.travelerIDs.contains($0.id) }.map(\.name)
    }

    private var shareText: String {
        "\(flight.displayNumber) · \(flight.origin.displayCode) → \(flight.destination.displayCode) — \(flight.countdownSummary)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                TabView(selection: $page) {
                    plainTextPage.tag(0)
                    routeMapPage.tag(1)
                    boardingPassPage.tag(2)
                    flightStatusPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dotIndicator

                ctaArea
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)
            }
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
                guard mapSnapshot == nil, let origin = flight.origin.coordinate, let destination = flight.destination.coordinate else { return }
                mapSnapshot = await Self.loadMapSnapshot(origin: origin, destination: destination)
            }
            .task {
                guard airlineLogo == nil, let url = flight.displayLogoURL else { return }
                if let (data, _) = try? await URLSession.shared.data(from: url) {
                    airlineLogo = UIImage(data: data)
                }
            }
        }
        .postHogScreenView("Flight Tracking: Share")
    }

    // MARK: - Pages

    private var plainTextPage: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            Text(shareText)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var routeMapPage: some View {
        VStack(spacing: Theme.Spacing.md) {
            RouteMapShareCard(flight: flight, mapSnapshot: mapSnapshot, stickerStyle: stickerStyle, airlineLogo: airlineLogo, travelerNames: travelerNames)
            FlightStickerStylePicker(selection: $stickerStyle)
        }
    }

    private var boardingPassPage: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            BoardingPassShareCard(flight: flight, style: stickerStyle, airlineLogo: airlineLogo, travelerNames: travelerNames)
            FlightStickerStylePicker(selection: $stickerStyle)
            Spacer(minLength: 0)
        }
    }

    private var flightStatusPage: some View {
        VStack {
            Spacer(minLength: 0)
            FlightStatusShareCard(flight: flight)
            Spacer(minLength: 0)
        }
    }

    private var dotIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.pageCount, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.ink : Theme.subtleInk.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - CTA row

    @ViewBuilder
    private var ctaArea: some View {
        if page == 0 {
            ShareLink(item: shareText) {
                Text("Share Text")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
        } else {
            ctaRow(image: currentPageImage())
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
                ShareLink(item: Image(uiImage: image), preview: SharePreview("Flight share", image: Image(uiImage: image))) {
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

    @MainActor
    private func currentPageImage() -> UIImage? {
        switch page {
        case 1: renderImage(RouteMapShareCard(flight: flight, mapSnapshot: mapSnapshot, stickerStyle: stickerStyle, airlineLogo: airlineLogo, travelerNames: travelerNames))
        case 2: renderImage(BoardingPassShareCard(flight: flight, style: stickerStyle, airlineLogo: airlineLogo, travelerNames: travelerNames))
        case 3: renderImage(FlightStatusShareCard(flight: flight))
        default: nil
        }
    }

    @MainActor
    private func renderImage<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = displayScale
        return renderer.uiImage
    }

    // MARK: - Map snapshot

    private static func loadMapSnapshot(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) async -> MKMapSnapshotter.Snapshot? {
        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        options.showsBuildings = false
        options.region = RouteMapShareCard.region(for: origin, destination)
        options.size = RouteMapShareCard.cardSize

        do {
            return try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
    }
}

#Preview {
    FlightShareView(flight: MockData.activeFlight)
        .environment(AppModel())
}
