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

    /// How far a pin's true coordinate must land inside the frame edge before `content(_:)`
    /// accepts it as-is rather than clamping. Shared between the fetch-time fit check
    /// (`loadMapSnapshot`'s retry loop) and this view's own render-time clamp
    /// (`clampToSafeArea`), so a pin that just barely didn't "fit" at fetch time still clamps to
    /// the exact same safe boundary at render time instead of two slightly different margins
    /// compounding. Deliberately tight — just past `pinAvatarRadius` — not sized to also keep the
    /// *label* clear of the edge: found via testing that pairs whose longitude separation
    /// approaches the geometric limit (Melbourne↔Buenos Aires, 156.7°; Mexico City↔Singapore,
    /// 157.0°) overshoot *any* generous margin by roughly the same ~26pt regardless of how far
    /// `loadMapSnapshot` zooms out — a single north-up region showing that much longitude is
    /// mathematically forced close to the frame edge, full stop. A larger inset (46, tuned assuming
    /// this was avoidable) was clamping both cities' real positions noticeably off their true spot
    /// for exactly these pairs; occasionally letting a long city name's label edge get cropped is a
    /// smaller visual cost than the avatar itself reading as being in the wrong place. Scaled with
    /// `mapSize` (originally 20 against a 328pt-wide frame, briefly 17 at 280pt) to keep the same
    /// relative margin as the card's own size changes.
    private static let inset: CGFloat = 18

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

    /// Even after `loadMapSnapshot`'s own retry loop, some pairs genuinely can't both land inside
    /// the safe inset margin at *any* north-up zoom — either close to true antipodes (~70km short
    /// of Earth's ~20,015km maximum, e.g. Córdoba↔Hamilton), or a pair whose *longitude* separation
    /// alone sits close to the 180° maximum even though their great-circle distance isn't extreme
    /// (Bangkok↔New York, 13,948km but 174.5° of longitude) — either way, a hard fact about the
    /// geometry, not a bug to keep chasing with a bigger span cap. `loadMapSnapshot` always returns
    /// its widest attempt regardless, so this always draws both cities' *real* coordinates — an
    /// earlier version swapped in a self-centered camera with a decorative line to a synthetic
    /// "exit point" for this case, which read as an actual (very wrong) pin placement once it sat
    /// on real, recognizable terrain (found via testing: Singapore's fictional exit-point pin
    /// landed in the Pacific off Mexico's coast) rather than the "stylized direction indicator" it
    /// was meant to be. Each pin instead clamps orthogonally toward the inset-safe rectangle —
    /// nudged the minimum distance needed to stay in frame, not walked arbitrarily far along the
    /// route toward the other city (tried first: kept the pin *on* the route, but for a pair this
    /// extreme dragged it noticeably away from its own true position). A single straight chord
    /// between the two (possibly clamped) points, not the full curved geodesic — a curve whose
    /// endpoints get clamped independently kinks into an unnaturally flat-bottomed box shape near
    /// an edge, and a real geodesic arc isn't especially meaningful over a crop already zoomed out
    /// to its absolute limit for this pair anyway.
    private func content(_ mapSnapshot: MKMapSnapshotter.Snapshot) -> some View {
        let myPoint = Self.clampToSafeArea(mapSnapshot.point(for: myCity.coordinate))
        let partnerPoint = Self.clampToSafeArea(mapSnapshot.point(for: partnerCity.coordinate))

        return ZStack {
            Image(uiImage: mapSnapshot.image)
            Path { path in
                path.move(to: myPoint)
                path.addLine(to: partnerPoint)
            }
            .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            pin(myPoint, photo: selfPhoto, tint: Theme.skyBlue, city: myCity)
            pin(partnerPoint, photo: partnerPhoto, tint: Theme.heartRed, city: partnerCity)
        }
    }

    private static func clampToSafeArea(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, inset), mapSize.width - inset),
            y: min(max(point.y, inset), mapSize.height - inset)
        )
    }

    /// `.imagery` satellite photography with `.flat` elevation (not the truly plain `.standard`
    /// road map `FlightMapView` itself uses, and not `.hybrid`) — `.flat` elevation is what keeps
    /// this reading as a flat map rather than a small globe; `.imagery` (rather than `.hybrid`) is
    /// what actually renders at the extreme zoom-out this file needs (this whole view only exists
    /// because a pair is too far apart for `DistanceGlobeView`'s own snapshot, which never needed
    /// anywhere near this range) — `.hybrid` bakes Apple's own city-name labels into the raster
    /// image, which caused real labels duplicating near our own pin at close zoom. `.imagery` has
    /// the identical photography with no text at all.
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
    /// span, with real margin left over for their labels — not a bug to keep chasing. Rather than
    /// switching to a self-centered fallback for those, this just returns its widest attempt as-is;
    /// `content(_:)` clamps both real coordinates into the safe-inset rectangle itself.
    static func loadMapSnapshot(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> MKMapSnapshotter.Snapshot? {
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
            let grownSpan = MKCoordinateSpan(
                latitudeDelta: min(span.latitudeDelta * 1.4, maxLatSpanForCenter),
                longitudeDelta: min(span.longitudeDelta * 1.4, maxSpan)
            )
            // Both axes already at their caps (`maxLatSpanForCenter`/`maxSpan`) — another
            // identical request would just refetch the same non-fitting snapshot. Found via
            // London↔Melbourne (16,898km, 145.1° of longitude): its span hits both caps on the
            // very first retry, so without this the remaining 4 attempts were pure wasted
            // MKMapSnapshotter round-trips (each real network+render latency) before returning
            // that same widest-attempt snapshot regardless.
            if grownSpan.latitudeDelta == span.latitudeDelta && grownSpan.longitudeDelta == span.longitudeDelta {
                break
            }
            span = grownSpan
        }

        // Never converged within the safe-inset margin at any north-up span — not always a
        // near-antipodal pair; a pair whose *longitude* separation alone sits close to the 180°
        // maximum hits this too (Bangkok↔New York, 174.5°), because a roughly-square frame showing
        // that much longitude is forced (Mercator being isotropic) to also show a huge, mostly-empty
        // *latitude* range to match — no amount of span/buffer tuning fixes that, it's the geometry
        // of a north-up rectangle. `lastSnapshot` is still the widest (most zoomed-out) attempt
        // reached, real coordinates and all — `content(_:)` clamps both pins into frame from here
        // rather than this function switching to a fabricated position for one of them.
        return lastSnapshot
    }

    private static let pinLabelOffset: CGFloat = 30

    /// Conservative half-width for the label pill's own edge-avoidance below — real width varies
    /// with the city name (`.minimumScaleFactor` lets long ones shrink rather than clip), but this
    /// covers a name as long as "Buenos Aires" at this font comfortably without needing to measure
    /// the actual rendered text.
    private static let labelHalfWidth: CGFloat = 40

    /// Avatar and label are positioned independently, not as one `VStack` shifted as a group —
    /// an earlier version centered the whole avatar+label group on `point` via a single hand-tuned
    /// vertical offset, which (found via testing several near-polar pairs) left the *label*, not
    /// the avatar, sitting almost exactly on `point`, since the offset had been tuned before the
    /// label existed in the group and never revisited. The route line, which always draws to the
    /// real `point`, then visibly touched the label pill instead of the avatar it belongs to.
    /// Positioning the avatar directly at `point` (matching `DistanceGlobeView.pin`'s own approach)
    /// makes that connection correct by construction. The label's *x* is independently clamped
    /// in from `point.x` when needed — `inset` (20pt) is deliberately tight around the avatar
    /// alone (see its own doc comment) and too small to also keep a ~70pt-wide label from clipping
    /// at the rounded-rect edge for a pin that sits right at that boundary; shifting just the label
    /// keeps the avatar circle exactly on its true/clamped position while the name next to it stays
    /// fully on-screen.
    private func pin(_ point: CGPoint, photo: UIImage?, tint: Color, city: Place) -> some View {
        let labelX = min(max(point.x, Self.labelHalfWidth), Self.mapSize.width - Self.labelHalfWidth)
        return Group {
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
                .position(x: labelX, y: point.y + Self.pinLabelOffset)
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
