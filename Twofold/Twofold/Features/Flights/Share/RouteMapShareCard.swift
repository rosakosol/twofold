//
//  RouteMapShareCard.swift
//  Twofold
//
//  "Show your flight story" — a real map background (`MKMapSnapshotter`, pre-fetched by
//  `FlightShareView`'s `.task`, never a live `Map`/`FlightMapView`: `ImageRenderer` can't reliably
//  rasterize either — same constraint `DistanceShareCard` already works around) with the
//  great-circle route hand-drawn on top via `Geo`'s public helpers, plus the customizable
//  `BoardingPassShareCard` sticker composited in the corner.
//

import SwiftUI
import MapKit

struct RouteMapShareCard: View {
    let flight: Flight
    let mapSnapshot: MKMapSnapshotter.Snapshot?
    var stickerStyle: FlightStickerStyle = .light
    var airlineLogo: UIImage? = nil
    var travelerNames: [String] = []

    static let cardSize = CGSize(width: 340, height: 400)

    /// Region padded well beyond the two endpoints so both pins and their labels land safely
    /// inside frame, with a sensible floor so a short domestic hop doesn't render as an
    /// unreadably tight zoom.
    static func region(for origin: CLLocationCoordinate2D, _ destination: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let center = Geo.sphericalMidpoint(origin, destination)
        let latDelta = max(abs(origin.latitude - destination.latitude) * 1.7, 10)
        let lonDelta = max(abs(origin.longitude - destination.longitude) * 1.7, 10)
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mapLayer
            watermark
            BoardingPassShareCard(flight: flight, style: stickerStyle, airlineLogo: airlineLogo, travelerNames: travelerNames, compact: true)
                .padding(Theme.Spacing.sm)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }

    @ViewBuilder
    private var mapLayer: some View {
        if let mapSnapshot, let origin = flight.origin.coordinate, let destination = flight.destination.coordinate {
            ZStack {
                Image(uiImage: mapSnapshot.image)
                routePath(mapSnapshot, origin: origin, destination: destination)
                endpointLabel(mapSnapshot.point(for: origin), code: flight.origin.displayCode, alignment: .bottom)
                endpointLabel(mapSnapshot.point(for: destination), code: flight.destination.displayCode, alignment: .top)
            }
            .frame(width: Self.cardSize.width, height: Self.cardSize.height)
            .clipped()
        } else {
            Color(hex: "0E2A52")
            ProgressView().tint(.white)
        }
    }

    /// Many short chords between closely-spaced great-circle samples, same technique
    /// `DistanceShareCard.normalGlobeContent` uses — a straight line pin-to-pin would cut the
    /// true geodesic arc rather than follow it.
    private func routePath(_ snapshot: MKMapSnapshotter.Snapshot, origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D) -> some View {
        Path { path in
            let sampleCount = 48
            let samples = (0...sampleCount).map { i in
                Geo.intermediateGreatCirclePoint(origin, destination, fraction: Double(i) / Double(sampleCount))
            }
            guard let first = samples.first else { return }
            path.move(to: snapshot.point(for: first))
            for coordinate in samples.dropFirst() {
                path.addLine(to: snapshot.point(for: coordinate))
            }
        }
        .stroke(flight.status.semanticColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 10]))
    }

    private func endpointLabel(_ point: CGPoint, code: String, alignment: VerticalAlignment) -> some View {
        VStack(spacing: 4) {
            if alignment == .top {
                Circle().fill(.white).frame(width: 8, height: 8)
                codeChip(code)
            } else {
                codeChip(code)
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
        .position(point)
        .offset(y: alignment == .top ? 14 : -14)
    }

    private func codeChip(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private var watermark: some View {
        TwofoldBrandMark(color: .white.opacity(0.85), size: 16, textStyle: .caption)
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    RouteMapShareCard(flight: MockData.activeFlight, mapSnapshot: nil)
        .padding()
        .background(Color.black)
}
