//
//  DistanceFlatMapView.swift
//  Twofold
//
//  The flat, non-globe map used once a pair is too far apart for `DistanceGlobeView`'s
//  spherical crop to hold both of them comfortably (see `DistanceMapView.flatMapThresholdKm` —
//  chosen empirically: the globe visibly starts cramping a partner's pin/label together well
//  before it's technically "off" it). Flat (not curved) elevation is what visually distinguishes
//  this from a small globe — see `loadMapSnapshot`'s own comment for why it still renders with
//  `.hybrid` satellite imagery rather than the plain road map that name might suggest.
//  A static `MKMapSnapshotter` render, not a live `MKMapView`/`Map` — there's no interactivity,
//  live position, or follow-camera need here, and a static snapshot is what lets the live reveal
//  screen and its share card render identically (`ImageRenderer` can't rasterize a live map).
//

import SwiftUI
import MapKit

struct DistanceFlatMapView: View {
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    /// Pre-fetched by the caller via `Self.loadMapSnapshot` — nil shows a loading placeholder.
    let mapSnapshot: MKMapSnapshotter.Snapshot?

    /// Matches `DistanceGlobeView.mapSize` so the two are interchangeable in the surrounding
    /// layout regardless of which one a given pair's distance selects.
    static let mapSize = DistanceGlobeView.mapSize

    private static let pinAvatarRadius: CGFloat = 16

    /// Reserved on every edge for the avatar+label stack — an endpoint's true coordinate needs to
    /// land this far inside the frame, not just anywhere inside it, or the label still clips even
    /// though the pin itself is technically "in frame." Shared between the fetch-time fit check
    /// (`loadMapSnapshot`) and this view's own render-time check, which must agree exactly, or a
    /// snapshot the loader considered "fits" could still get rendered in fallback mode, or vice
    /// versa.
    private static let inset: CGFloat = 46

    var body: some View {
        ZStack {
            if let mapSnapshot {
                content(mapSnapshot)
            } else {
                Color(hex: "0E2A52")
                ProgressView().tint(.white)
            }
        }
        .frame(width: Self.mapSize.width, height: Self.mapSize.height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Even after `loadMapSnapshot`'s own retry loop, some pairs genuinely can't both appear in one
    /// flat top-down camera view at *any* zoom — either close to true antipodes (~70km short of
    /// Earth's ~20,015km maximum, e.g. Córdoba↔Hamilton), or, less obviously, a pair whose
    /// *longitude* separation alone sits close to the 180° maximum even though their great-circle
    /// distance isn't extreme (Bangkok↔New York, 13,948km but 174.5° of longitude) — either way, a
    /// hard fact about the geometry, not a bug to keep chasing with a bigger span cap. This checks
    /// the same way the loader did (partner's real point against the same `inset`) and, if it
    /// still doesn't fit, switches to a self-centered layout: myCity's real pin plus a straight
    /// line (not the full curved geodesic, which would arc off toward a destination that was never
    /// going to be on screen) to where that line exits the frame — partner's own pin sits right
    /// there, always inside the frame by construction.
    @ViewBuilder
    private func content(_ mapSnapshot: MKMapSnapshotter.Snapshot) -> some View {
        let myPoint = mapSnapshot.point(for: myCity.coordinate)
        let partnerPoint = mapSnapshot.point(for: partnerCity.coordinate)
        let partnerFits = partnerPoint.x >= Self.inset && partnerPoint.x <= Self.mapSize.width - Self.inset
            && partnerPoint.y >= Self.inset && partnerPoint.y <= Self.mapSize.height - Self.inset

        ZStack {
            Image(uiImage: mapSnapshot.image)
            if partnerFits {
                routePath(mapSnapshot)
                pin(myPoint, photo: selfPhoto, tint: Theme.skyBlue, city: myCity)
                pin(partnerPoint, photo: partnerPhoto, tint: Theme.heartRed, city: partnerCity)
            } else {
                // Both ends of this decorative line are placed from frame geometry, not from
                // `myPoint` itself — the self-centered camera this branch's snapshot comes from
                // always renders `myCity` at (or extremely near) the exact frame center by
                // construction (`MKMapCamera(lookingAtCenter: myCity.coordinate, ...)`), so a ray
                // drawn from `myPoint` only ever used *half* the frame (center to one edge).
                // Drawing a full chord through the center instead — exiting the inset-safe
                // rectangle in *both* the bearing direction and its reverse — uses the frame's
                // entire width/diagonal, roughly doubling how much of the card the pins and route
                // actually span. This also decouples the pins' layout from the self-centered
                // camera's own zoom level entirely (found via testing: changing camera distance
                // alone visibly changed only the background terrain, never the fixed edge-to-edge
                // ray, which is exactly why "zoom in more" wasn't fixed by camera tuning alone).
                let center = CGPoint(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2)
                let bearing = Self.rhumbBearing(from: myCity.coordinate, to: partnerCity.coordinate) * .pi / 180
                let direction = CGPoint(x: sin(bearing), y: -cos(bearing))
                let origin = Self.rectExitPoint(from: center, direction: CGPoint(x: -direction.x, y: -direction.y), size: Self.mapSize, inset: Self.inset)
                let exit = Self.rectExitPoint(from: center, direction: direction, size: Self.mapSize, inset: Self.inset)
                Path { path in
                    path.move(to: origin)
                    path.addLine(to: exit)
                }
                .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                pin(origin, photo: selfPhoto, tint: Theme.skyBlue, city: myCity)
                pin(exit, photo: partnerPhoto, tint: Theme.heartRed, city: partnerCity)
            }
        }
    }

    /// Where a ray from `start` heading in `direction` exits the inset-safe rectangle — the
    /// standard slab/parametric ray-box intersection, solved per axis and taking whichever edge
    /// it reaches first.
    private static func rectExitPoint(from start: CGPoint, direction: CGPoint, size: CGSize, inset: CGFloat) -> CGPoint {
        let minX = inset, maxX = size.width - inset
        let minY = inset, maxY = size.height - inset
        var t = CGFloat.greatestFiniteMagnitude
        if direction.x > 0.0001 { t = min(t, (maxX - start.x) / direction.x) }
        if direction.x < -0.0001 { t = min(t, (minX - start.x) / direction.x) }
        if direction.y > 0.0001 { t = min(t, (maxY - start.y) / direction.y) }
        if direction.y < -0.0001 { t = min(t, (minY - start.y) / direction.y) }
        if !t.isFinite || t < 0 { t = 0 }
        return CGPoint(x: start.x + t * direction.x, y: start.y + t * direction.y)
    }

    /// The *rhumb line* bearing (constant compass heading — the direction of a straight line on a
    /// flat Mercator map) rather than the great circle's own initial bearing, deliberately, for
    /// this one decorative fallback line: a great circle's initial bearing points toward wherever
    /// the *shortest path* first heads, which for a route that bows toward a pole (Bangkok↔New
    /// York, whose true shortest path initially heads almost due north) reads as "myCity's partner
    /// is up that way" — geometrically correct, but exactly backwards from how a couple actually
    /// pictures being "that far apart," which is much more about the huge east-west gulf between
    /// them (174.5° of longitude, most of the total distance) than the modest latitude change. The
    /// rhumb bearing points in the direction that actually dominates the separation instead.
    private static func rhumbBearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        var Δλ = (b.longitude - a.longitude) * .pi / 180
        if Δλ > .pi { Δλ -= 2 * .pi }
        if Δλ < -.pi { Δλ += 2 * .pi }
        let Δψ = log(tan(.pi / 4 + φ2 / 2) / tan(.pi / 4 + φ1 / 2))
        let θ = atan2(Δλ, Δψ) * 180 / .pi
        return θ.truncatingRemainder(dividingBy: 360) + (θ < 0 ? 360 : 0)
    }

    /// `.imagery` satellite photography with `.flat` elevation (not the truly plain `.standard`
    /// road map `FlightMapView` itself uses, and not `.hybrid`) — `.flat` elevation is what keeps
    /// this reading as a flat map rather than a small globe; `.imagery` (rather than `.hybrid`) is
    /// what actually renders at the extreme zoom-out this file needs (this whole view only exists
    /// because a pair is too far apart for `DistanceGlobeView`'s own snapshot, which never needed
    /// anywhere near this range) — `.hybrid` bakes Apple's own city-name labels into the raster
    /// image, which caused two confusions: real labels duplicating near our own pin at close zoom,
    /// and, worse, in the self-centered fallback below, real nearby city names (Ho Chi Minh City,
    /// Manila...) sitting right next to our fictional exit-point pin for a city that was never
    /// really there, undermining the "this is a stylized direction indicator, not a real position"
    /// read the fallback depends on. `.imagery` has the identical photography with no text at all.
    ///
    /// Region-based framing (`options.region`, an `MKCoordinateSpan` in real degrees) — the same
    /// technique `DistanceGlobeView` already uses successfully up to 110°, grown further here (up
    /// to 178°, just short of the antimeridian-degenerate 180°). A single analytically-computed
    /// camera distance was tried first and outright failed for some pairs (myCity landing
    /// completely outside the frame for a route that bows up near a pole); a camera distance grown
    /// across retries looked identically stuck at every attempt too, but that turned out to be a
    /// red herring — the retry loop had simply reached its own `maxSpan` cap on its first attempt
    /// and kept re-requesting that same capped value, not a real MapKit ceiling (confirmed on
    /// macOS: `MKMapSnapshotter` scales a region smoothly all the way to 178° with no clamping).
    /// The real, honest finding underneath that confusion: some pairs (Melbourne↔New York, ~150°
    /// apart) genuinely don't both fit in this card's `mapSize` even at the true maximum useful
    /// span, with real margin left over for their labels — not a bug to keep chasing, the reason
    /// `content(_:)` below has its own self-centered fallback layout.
    static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> MKMapSnapshotter.Snapshot? {
        let distanceKm = Geo.distanceKm(a, b)
        let samples = routeSamples(from: a, to: b)
        let points = unwrappedMapPoints(for: samples)
        let worldWidth = MKMapSize.world.width
        // The region's own center: a simple lat/lon average of the two real *endpoints*
        // (antimeridian-safe for longitude) — not the sampled route's own bounding-box center
        // (an earlier version, which fixed the previous bug of using `Geo.sphericalMidpoint`'s
        // arc midpoint, but introduced a subtler version of the same problem: a route that bows
        // steeply toward a pole, e.g. Bangkok↔New York peaking near the Arctic, pulled that
        // bounding-box center's own latitude up toward the peak too, leaving less headroom before
        // the *span* needed to reach back down to the real, lower-latitude endpoints pushed the
        // region past the pole and silently broke `MKCoordinateRegion` — same failure mode as
        // `DistanceGlobeView`'s arc-midpoint bug, just reached a different way). Real cities are
        // never at the pole, so centering on them directly and sizing the span to reach the
        // route's actual extent *from* that center (below) doesn't run into this at all.
        var lonDelta = b.longitude - a.longitude
        if lonDelta > 180 { lonDelta -= 360 }
        if lonDelta < -180 { lonDelta += 360 }
        var centerLongitude = a.longitude + lonDelta / 2
        if centerLongitude > 180 { centerLongitude -= 360 }
        if centerLongitude < -180 { centerLongitude += 360 }
        let centerLatitude = (a.latitude + b.latitude) / 2
        let center = CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)

        // How far the two real *endpoints* reach from that center, in each direction — not the
        // full sampled route's own extent (an earlier version measured every sample, including a
        // route's bowed peak). Since `center` is the endpoints' own lat/lon average, each
        // endpoint's deviation from it is just half the raw lat/lon difference regardless of how
        // far the geodesic between them bows — sizing the span from that, rather than the peak,
        // keeps close-but-longitude-extreme pairs (Reykjavik↔Tokyo, a route that bows near the
        // pole despite the cities themselves sitting only moderately far apart) tightly cropped
        // around the two pins instead of zoomed out to fit a bow the pins never actually reach
        // the edge of — the curved route drawn later can simply run off-frame at the top where it
        // peaks, same as it would off the edge of any real Mercator map. The retry loop below
        // still grows this if the two real endpoints don't end up fitting.
        let centerX = points[0].x + (lonDelta / 360) * worldWidth / 2
        let maxLatDeviation = max(abs(a.latitude - centerLatitude), abs(b.latitude - centerLatitude))
        let maxLonDeviation = max(abs(points[0].x - centerX), abs(points[points.count - 1].x - centerX))
        let latSpanDegrees = maxLatDeviation * 2
        let lonSpanDegrees = maxLonDeviation / worldWidth * 360 * 2

        let options = MKMapSnapshotter.Options()
        options.size = mapSize
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)

        // However far the route's own bow needs to reach, this never lets the *requested* span
        // push the region past the pole — `MKCoordinateRegion` silently breaks (not just crops)
        // once `center.latitude ± span.latitudeDelta / 2` exceeds ±90°.
        let maxLatSpanForCenter = 2 * min(90 - centerLatitude, 90 + centerLatitude) - 4
        let maxSpan = 178.0
        // `1.3`, not the `1.8` an earlier version used — that was tuned back when this measured
        // the whole route's own bow rather than just the two endpoints (see above), a much larger
        // base value that needed less relative padding to converge on the first attempt. Against
        // the now-smaller endpoint-based base, `1.8` was leaving pins with far more margin than
        // `inset` actually requires, zooming out more than necessary — a smaller buffer here,
        // backstopped by the retry loop below (which still grows the span 1.4x per attempt, up to
        // 6 times, if this undershoots), gets pins closer to filling the frame without giving up
        // the safety net for when it doesn't converge immediately.
        var span = MKCoordinateSpan(
            latitudeDelta: min(max(latSpanDegrees * 1.3, 10), maxLatSpanForCenter),
            longitudeDelta: min(max(lonSpanDegrees * 1.3, 10), maxSpan)
        )
        var lastSnapshot: MKMapSnapshotter.Snapshot?
        for _ in 0..<6 {
            options.region = MKCoordinateRegion(center: center, span: span)
            guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return lastSnapshot }
            lastSnapshot = snapshot
            let fits = [a, b].allSatisfy { coordinate in
                let point = snapshot.point(for: coordinate)
                return point.x >= inset && point.x <= mapSize.width - inset
                    && point.y >= inset && point.y <= mapSize.height - inset
            }
            if fits { return snapshot }
            span = MKCoordinateSpan(
                latitudeDelta: min(span.latitudeDelta * 1.4, maxLatSpanForCenter),
                longitudeDelta: min(span.longitudeDelta * 1.4, maxSpan)
            )
        }

        // Never converged in a north-up `MKCoordinateRegion` — not always a near-antipodal pair
        // (see `content(_:)`'s own comment for that case); a pair whose *longitude* separation
        // alone sits close to the 180° maximum hits this too (Bangkok↔New York, 174.5°), because a
        // roughly-square frame showing that much longitude is forced (Mercator being isotropic) to
        // also show a huge, mostly-empty *latitude* range to match — no amount of span/buffer
        // tuning fixes that, it's the geometry of a north-up rectangle. So `content(_:)` draws
        // myCity's real pin plus a straight decorative line to wherever it exits the frame, and
        // this just needs one more snapshot centered on myCity to draw that over.
        //
        // How far to zoom that self-centered camera out scales with the pair's own real
        // `distanceKm`, not a flat constant — found via testing both a genuinely far pair
        // (Bangkok↔New York, 13,948km, where `20_000_000m` read as deliberate "here's your side of
        // the world" context) and a much closer one that still lands here for the same longitude
        // reason (Reykjavik↔Tokyo, 8,820km, confirmed via a temporary debug overlay that the real
        // Tokyo point never fits even at that same `20_000_000m` — so it was *always* the ray
        // fallback for this pair too, just with the same wide, mostly-empty framing as the much
        // further-apart Bangkok↔New York, which is exactly why "zoom in more" read as correct
        // feedback here despite `20_000_000m` being right for that other pair).
        //
        // Squared, not linear, against the `13,948km` (Bangkok↔New York) reference point that
        // `20_000_000m` was tuned against — a first attempt scaled linearly (`distanceKm * 1_434`),
        // which only pulled Reykjavik↔Tokyo in to `12.65M` (a 37% cut) and user-tested as barely
        // perceptible, reading as the camera merely panning rather than zooming. Squaring the ratio
        // keeps the top of the curve anchored at the same proven `20_000_000m` for pairs actually
        // near that reference distance, while falling off much faster below it — the same
        // `8,820km` pair now lands at `8.0M` (a 60% cut), a difference big enough to actually read
        // as "zoomed in" rather than noise.
        let baseDistance = min(max(20_000_000 * pow(distanceKm / 13_948, 2), 4_000_000), 20_000_000)
        let candidateDistances: [CLLocationDistance] = [0.3, 0.5, 0.7, 1.0].map { $0 * baseDistance }
        var widestSnapshot: MKMapSnapshotter.Snapshot?
        for distance in candidateDistances {
            let selfCenteredOptions = MKMapSnapshotter.Options()
            selfCenteredOptions.size = mapSize
            selfCenteredOptions.camera = MKMapCamera(lookingAtCenter: a, fromDistance: distance, pitch: 0, heading: 0)
            guard let snapshot = try? await MKMapSnapshotter(options: selfCenteredOptions).start() else { continue }
            widestSnapshot = snapshot
            // A tighter candidate that happens to also catch the partner's real point (rare, but
            // possible for a pair close to the threshold) beats the ray fallback outright —
            // `content(_:)` already renders whichever one the returned snapshot supports.
            let partnerPoint = snapshot.point(for: b)
            let partnerFits = partnerPoint.x >= inset && partnerPoint.x <= mapSize.width - inset
                && partnerPoint.y >= inset && partnerPoint.y <= mapSize.height - inset
            if partnerFits { return snapshot }
        }
        return widestSnapshot ?? lastSnapshot
    }

    /// Many short chords between closely-spaced great-circle samples — a straight line pin-to-pin
    /// would cut the true geodesic arc (and for a long route, visibly so) rather than follow it.
    private func routePath(_ snapshot: MKMapSnapshotter.Snapshot) -> some View {
        Path { path in
            let sampleCount = 96
            let samples = (0...sampleCount).map { i in
                Geo.intermediateGreatCirclePoint(myCity.coordinate, partnerCity.coordinate, fraction: Double(i) / Double(sampleCount))
            }
            guard let first = samples.first else { return }
            path.move(to: snapshot.point(for: first))
            for coordinate in samples.dropFirst() {
                path.addLine(to: snapshot.point(for: coordinate))
            }
        }
        .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private static let pinLabelOffset: CGFloat = 30

    /// Avatar and label are positioned independently, not as one `VStack` shifted as a group —
    /// an earlier version centered the whole avatar+label group on `point` via a single hand-tuned
    /// vertical offset, which (found via testing several near-polar pairs) left the *label*, not
    /// the avatar, sitting almost exactly on `point`, since the offset had been tuned before the
    /// label existed in the group and never revisited. The route line, which always draws to the
    /// real `point`, then visibly touched the label pill instead of the avatar it belongs to.
    /// Positioning the avatar directly at `point` (matching `DistanceGlobeView.pin`'s own approach)
    /// makes that connection correct by construction.
    private func pin(_ point: CGPoint, photo: UIImage?, tint: Color, city: Place) -> some View {
        Group {
            avatarCircle(photo, tint: tint)
                .position(point)
            Text(city.displayCity)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .position(x: point.x, y: point.y + Self.pinLabelOffset)
        }
    }

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
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    // MARK: - Great-circle sampling + antimeridian unwrap (ported from `FlightMapView`)

    private static func routeSamples(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let sampleCount = 300
        var coordinates: [CLLocationCoordinate2D] = [a]
        for i in 1..<sampleCount {
            coordinates.append(Geo.intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)))
        }
        coordinates.append(b)
        return coordinates
    }

    /// `MKMapPoint.x` runs monotonically west-to-east across a single flat Mercator strip — it has
    /// no concept of "the short way around." Unwrapping longitude incrementally across the
    /// sequence keeps every sample's x consistent even where the curve crosses the antimeridian,
    /// so the fitted bounds span the route's real short way across rather than jumping back
    /// around through the opposite hemisphere.
    private static func unwrappedMapPoints(for samples: [CLLocationCoordinate2D]) -> [MKMapPoint] {
        var points = samples.map { MKMapPoint($0) }
        let worldWidth = MKMapSize.world.width
        for i in 1..<points.count {
            while points[i].x - points[i - 1].x > worldWidth / 2 { points[i].x -= worldWidth }
            while points[i].x - points[i - 1].x < -worldWidth / 2 { points[i].x += worldWidth }
        }
        return points
    }
}

#Preview {
    DistanceFlatMapView(
        myCity: Place.commonCities.first { $0.city == "Melbourne" }!,
        partnerCity: Place.commonCities.first { $0.city == "New York" }!,
        selfPhoto: nil,
        partnerPhoto: nil,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}
