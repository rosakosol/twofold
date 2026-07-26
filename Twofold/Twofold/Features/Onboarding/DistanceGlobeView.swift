//
//  DistanceGlobeView.swift
//  Twofold
//
//  Onboarding's own version of `DistanceShareCard`'s proven "how far apart are we" 3D globe
//  render (Home's already-shipped distance card) — same dual-pin, overscan-crop technique, ported
//  wholesale rather than re-derived because it already solves a problem onboarding's own
//  from-scratch live-`Map` attempt kept fighting: a circular clip crops away MapKit's attribution
//  wordmark (baked into the snapshot's corner) for free. Takes raw photo `Data`/a tint instead of
//  `Person`/`Couple`, since onboarding has no account/couple model yet at this point in the flow.
//
//  Only ever used for pairs within `DistanceMapView.flatMapThresholdKm` — beyond that,
//  `DistanceFlatMapView` takes over instead of a "both pins share one globe or one gets a floating
//  card" branch this used to have. That branch is gone: testing it at a spread of distances (10k
//  through 17k km) showed the globe visibly cramping a pin/label together well before the pair
//  crossed into "can't share a globe at all" territory, and even a shifted/widened crop could
//  never fit both past roughly 15,000km (the two cities' angular separation by then exceeds what
//  any reasonably-sized crop can hold, full stop) — not worth chasing further when a flat map
//  handles the whole "too far apart for one globe" range accurately instead.
//

import SwiftUI
import MapKit

struct DistanceGlobeView: View {
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    /// Pre-fetched by the caller via `Self.loadMapSnapshot` — nil shows a loading placeholder.
    let mapSnapshot: MKMapSnapshotter.Snapshot?

    static let mapSize = CGSize(width: 328, height: 300)
    static let globeSize: CGFloat = 280

    /// MapKit's globe-mode renderer always leaves some black space/limb margin around the sphere
    /// regardless of how tight the snapshot's region span is — scaling the whole composited image
    /// up (map photo + path + pins together, so they stay aligned to their real sphere positions)
    /// and clipping afterward crops that margin (and MapKit's own attribution wordmark, which
    /// lands in it) away reliably instead. `1.45` was tuned for the region span this view used to
    /// request (110°) — widening that span to 120° (to fix pins landing on unrecognizable
    /// generic terrain — see `loadMapSnapshot`'s own comment) shrinks the globe's apparent size
    /// within the same fixed output size, so the old overscan no longer fully crops the margin.
    private static let globeOverscan: CGFloat = 1.52

    var body: some View {
        ZStack {
            if let mapSnapshot {
                globeContent(mapSnapshot)
            } else {
                Color(hex: "0E2A52")
                ProgressView().tint(.white)
            }
        }
        .frame(width: Self.mapSize.width, height: Self.mapSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// A real globe snapshot (`.hybrid(elevation: .realistic)`, the same configuration
    /// `RelationshipGlobeView`'s live `Map` uses).
    ///
    /// Centered on the two cities' own simple lat/lon average, not `Geo.sphericalMidpoint` (the
    /// great-circle *arc* midpoint) — for a pair whose route bows steeply toward a pole (Tokyo↔
    /// London peaks over Siberia), the arc midpoint itself can land very close to that pole, and
    /// `MKCoordinateRegion` silently clamps how much area it can show once a region's center is
    /// near enough to one: increasing the requested span past a point had *zero* further effect
    /// (confirmed by testing — 110°, 150°, `.realistic`, `.flat`, all rendered pixel-identical),
    /// not because of some MapKit-wide span ceiling (a macOS test showed `.flat` scaling smoothly
    /// to 178° elsewhere), but specifically because the *center* was pole-adjacent. Averaging the
    /// endpoints' own latitudes instead keeps the center near the cities' actual latitudes, clear
    /// of that problem, at the cost of not being the mathematically "true" arc midpoint — a
    /// trade worth making since it's what keeps both real cities recognizably in frame at all.
    static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> MKMapSnapshotter.Snapshot? {
        var lonDelta = b.longitude - a.longitude
        if lonDelta > 180 { lonDelta -= 360 }
        if lonDelta < -180 { lonDelta += 360 }
        var centerLongitude = a.longitude + lonDelta / 2
        if centerLongitude > 180 { centerLongitude -= 360 }
        if centerLongitude < -180 { centerLongitude += 360 }
        let center = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: centerLongitude)

        // Was a flat 120° regardless of how far apart the pair actually is — fine for pairs near
        // the globe's own upper range (close to `DistanceMapView.flatMapThresholdKm`), but for a
        // genuinely close pair (Melbourne↔Sydney, 714km) it zoomed out so far past their real
        // separation that both pins landed almost on top of each other. Scaling the span with the
        // real angular separation (roughly km / 111.2, the km-per-degree of a great circle) keeps
        // close pairs meaningfully zoomed in, while `min(…, 120)` preserves the exact framing
        // already verified to work for pairs near the globe's own distance ceiling.
        let separationDegrees = Geo.distanceKm(a, b) / 111.2
        let span = min(max(separationDegrees * 1.35, 14), 120)

        let options = MKMapSnapshotter.Options()
        // `.imagery`, not `.hybrid` — hybrid overlays Apple's own city-name labels on top of the
        // satellite photo, and at this tight a zoom those labels frequently duplicate (the same
        // city rendered twice at different tile-boundary offsets) or land far from our own pin, so
        // the map visibly disagreed with itself about where a city "really" was. Confirmed via a
        // temporary debug crosshair drawn at the exact unclamped `snapshot.point(for:)` result —
        // it landed exactly under our pin every time, so the pins were never wrong; only Apple's
        // competing labels were confusing. `.imagery` shows the same photography with no text at
        // all, leaving our own pin + label pill as the only names on the globe.
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
        options.showsBuildings = false
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
        options.size = CGSize(width: globeSize, height: globeSize)

        do {
            return try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
    }

    /// Clamping every sample of the route independently (an earlier attempt, made to guarantee
    /// the line touches wherever the pins landed) fixed the disconnection but introduced a worse
    /// problem: clamping distorts the curve's own *shape*, since each point gets pulled toward
    /// the safe rectangle independently of its neighbors — for Tokyo↔London this showed up as a
    /// visibly kinked, unnaturally bent line rather than a smooth geodesic arc. The correct fix
    /// keeps every drawn sample at its true, unclamped projected position — only the *range* of
    /// the route that gets drawn is trimmed, to `[lower, upper]` (found by `safeGlobePoint`
    /// walking in from each city toward the other until it lands somewhere safe to draw a pin),
    /// so the line is always a genuine, undistorted piece of the real arc, and by construction
    /// still reaches exactly to wherever both pins are.
    private func globeContent(_ mapSnapshot: MKMapSnapshotter.Snapshot) -> some View {
        let (myPoint, tA) = safeGlobePoint(from: myCity.coordinate, toward: partnerCity.coordinate, snapshot: mapSnapshot)
        let (partnerPoint, sB) = safeGlobePoint(from: partnerCity.coordinate, toward: myCity.coordinate, snapshot: mapSnapshot)
        let tB = 1 - sB
        let lower = min(tA, tB), upper = max(tA, tB)

        return ZStack {
            // The sphere image + route, clipped to the circle — this layer alone, so a label
            // near the globe's edge (below) isn't cut off by that same circular mask even when
            // it's still safely inside the *outer* card.
            ZStack {
                Image(uiImage: mapSnapshot.image)
                    .resizable()
                    .scaledToFill()

                // Many short chords between closely-spaced great-circle samples, over the trimmed
                // `[lower, upper]` range — a single line straight from pin to pin would cut the
                // true geodesic arc; the full untrimmed route would run past a pin that had to be
                // walked in from its true, off-frame position.
                Path { path in
                    let sampleCount = 60
                    let samples = (0...sampleCount).map { i -> CGPoint in
                        let t = lower + (upper - lower) * Double(i) / Double(sampleCount)
                        let coordinate = Geo.intermediateGreatCirclePoint(myCity.coordinate, partnerCity.coordinate, fraction: t)
                        return mapSnapshot.point(for: coordinate)
                    }
                    guard let first = samples.first else { return }
                    path.move(to: first)
                    for point in samples.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color(hex: "6FD3FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 11]))
            }
            .frame(width: Self.globeSize, height: Self.globeSize)
            .scaleEffect(Self.globeOverscan)
            .clipShape(Circle())
            .position(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2)

            // Pins get the identical scale+position transform (so they still land on the exact
            // spot the map layer projects their city to) but aren't clipped to the circle — only
            // the outer card's own bounds constrain them from here.
            ZStack {
                pin(photo: selfPhoto, tint: Theme.skyBlue, city: myCity, at: myPoint)
                pin(photo: partnerPhoto, tint: Theme.heartRed, city: partnerCity, at: partnerPoint)
            }
            .frame(width: Self.globeSize, height: Self.globeSize)
            .scaleEffect(Self.globeOverscan)
            .position(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2)
        }
    }

    /// Walks real samples along the geodesic from `coordinate` toward `other` (0 = `coordinate`,
    /// 1 = `other`) and returns the first one that lands inside the safe display area, along with
    /// how far along the route that was — `globeContent` uses the fraction to trim the drawn line
    /// to match. Falls back to the midpoint (always safe, and always on the route) in the
    /// near-impossible case no sample qualifies.
    private func safeGlobePoint(from coordinate: CLLocationCoordinate2D, toward other: CLLocationCoordinate2D, snapshot: MKMapSnapshotter.Snapshot) -> (point: CGPoint, fraction: Double) {
        let steps = 60
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let sample = Geo.intermediateGreatCirclePoint(coordinate, other, fraction: fraction)
            let point = snapshot.point(for: sample)
            if isSafeGlobePoint(point) { return (point, fraction) }
        }
        let midpoint = Geo.intermediateGreatCirclePoint(coordinate, other, fraction: 0.5)
        return (snapshot.point(for: midpoint), 0.5)
    }

    private func isSafeGlobePoint(_ point: CGPoint) -> Bool {
        point.x >= Self.pinMargin && point.x <= Self.globeSize - Self.pinMargin
            && point.y >= Self.pinMinY && point.y <= Self.pinMaxY
    }

    /// Deliberately shrinks the outer card bounds *before* solving any of the margins below —
    /// those solve for a label touching the outer edge exactly, with zero slack for the card's
    /// own rounded corners or any small rounding in the constants they're built from, so a real
    /// pin could still graze the edge. Shaving a few points off the usable bounds up front
    /// applies the same safety margin to every derived value consistently.
    private static let edgeSafetyBuffer: CGFloat = 10

    /// Solves for the local-space x that keeps a scaled label pill's far edge exactly at the
    /// outer card's own edge, once this whole pin layer is scaled up by `globeOverscan` and
    /// repositioned at the card's center.
    private static let pinMargin: CGFloat = {
        let labelHalfWidth: CGFloat = 35
        let outerHalfWidth = mapSize.width / 2 - edgeSafetyBuffer
        let localHalfWidth = globeSize / 2
        let innerOuter = max(0, outerHalfWidth - labelHalfWidth * globeOverscan)
        return localHalfWidth - innerOuter / globeOverscan
    }()

    private static let pinAvatarRadius: CGFloat = 16
    private static let pinLabelOffset: CGFloat = 30
    private static let pinLabelHalfHeight: CGFloat = 13

    private static let pinMinY: CGFloat = {
        let outerHalfHeight = mapSize.height / 2 - edgeSafetyBuffer
        let localCenter = globeSize / 2
        return localCenter - (outerHalfHeight - pinAvatarRadius * globeOverscan) / globeOverscan
    }()

    private static let pinMaxY: CGFloat = {
        let outerHalfHeight = mapSize.height / 2 - edgeSafetyBuffer
        let localCenter = globeSize / 2
        return localCenter - pinLabelOffset - pinLabelHalfHeight + outerHalfHeight / globeOverscan
    }()

    private func pin(photo: UIImage?, tint: Color, city: Place, at point: CGPoint) -> some View {
        let labelWidth: CGFloat = 70
        let clampedX = min(max(point.x, labelWidth / 2 + 4), Self.globeSize - labelWidth / 2 - 4)
        return Group {
            avatarCircle(photo, tint: tint)
                .position(point)
            Text(city.displayCity)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: labelWidth)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: clampedX, y: point.y + Self.pinLabelOffset)
        }
    }

    /// Same visual recipe as `AvatarView(showsRing: true)` — frame, clip to circle, white ring,
    /// soft shadow — just built from a raw `UIImage?` instead of a `Person`, since onboarding has
    /// no account model yet at this point in the flow.
    private func avatarCircle(_ photo: UIImage?, tint: Color) -> some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: Self.pinAvatarRadius * 2, height: Self.pinAvatarRadius * 2)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

#Preview {
    DistanceGlobeView(
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "Singapore" }!,
        selfPhoto: nil,
        partnerPhoto: nil,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}
