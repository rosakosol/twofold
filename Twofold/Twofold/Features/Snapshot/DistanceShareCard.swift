//
//  DistanceShareCard.swift
//  Twofold
//
//  The shareable "how far apart are we right now" card — a static composite (a real curved 3D
//  globe snapshot, same `.hybrid(elevation: .realistic)` rendering `RelationshipGlobeView`'s live
//  `Map` uses + a hand-drawn geodesic path + avatar pins), not a live `Map` itself.
//  `ImageRenderer` can't reliably rasterize a live MapKit-backed SwiftUI `Map` that's never
//  actually been placed in a window (tiles haven't loaded, so there's nothing to capture) — the
//  same constraint `RelationshipStatsShareCard` and `SnapshotShareView` already work around via
//  `MKMapSnapshotter`.
//

import SwiftUI
import MapKit

struct DistanceShareCard: View {
    let couple: Couple
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double
    var theme: DistanceShareTheme = .classic
    /// Pre-rendered by the caller (`DistanceShareView`, via `MKMapSnapshotter`) — a network-
    /// backed map snapshot can't be generated synchronously inside `body`, and this view needs
    /// to render identically whether it's on-screen or being captured by `ImageRenderer`. Sized
    /// and regioned differently depending on `isOffGlobe` — see `DistanceShareView.loadMapSnapshot`.
    let mapSnapshot: MKMapSnapshotter.Snapshot?

    static let mapSize = CGSize(width: 328, height: 300)

    /// Beyond this, the two of you are far enough apart (roughly antipodal-adjacent) that both
    /// pins can't land within the same tightly-cropped globe view at once — past about 70° of
    /// angular separation from your own spherical midpoint, right at or beyond the visible
    /// hemisphere once the crop needed to fill the frame with no black space margin is applied.
    static let offGlobeThresholdKm: Double = 14_000
    /// The dual-pin globe (both of you close enough to share one view) — centered on your
    /// spherical midpoint, sized to fill nearly the whole card.
    static let normalGlobeSize: CGFloat = 280
    /// The single-pin globe used once you're past `offGlobeThresholdKm` — centered on *your*
    /// city only, smaller and left-biased so the card has room for partner's floating card.
    static let offGlobeSize: CGFloat = 210

    private static let offGlobeCenter = CGPoint(x: 118, y: 148)
    private static let offGlobeRadius: CGFloat = offGlobeSize / 2
    private static let floatingCardCenter = CGPoint(x: 278, y: 78)
    /// MapKit's globe-mode renderer always leaves some black space/limb margin around the
    /// sphere regardless of how tight the snapshot's region span is — scaling the whole
    /// composited image up (map photo + path + pins together, so they stay aligned to their real
    /// sphere positions) and clipping afterward crops that margin away reliably instead.
    private static let globeOverscan: CGFloat = 1.45

    private var comparison: Geo.DistanceComparison { Geo.bestDistanceComparison(km: distanceKm) }
    var isOffGlobe: Bool { distanceKm > Self.offGlobeThresholdKm }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: theme.primaryTextColor, size: 30, textStyle: .title3)

            VStack(spacing: 6) {
                Text("THE DISTANCE BETWEEN YOU")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(theme.secondaryTextColor)

                Text(MeasurementPreference.distanceLabel(km: distanceKm))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryTextColor)

                Text("\(comparison.percent, format: .number.precision(.fractionLength(comparison.percent < 1 ? 2 : 1)))% \(comparison.phrase) \(comparison.emoji)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accentTextColor)
            }

            globeCard
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var backgroundGradient: some View {
        ZStack {
            theme.backgroundGradient
            RadialGradient(colors: [theme.glowColor.opacity(0.4), .clear], center: .top, startRadius: 10, endRadius: 340)
        }
    }

    @ViewBuilder
    private var globeCard: some View {
        ZStack {
            if let mapSnapshot {
                if isOffGlobe {
                    offGlobeContent(mapSnapshot)
                } else {
                    normalGlobeContent(mapSnapshot)
                }
            } else {
                Color(hex: "0E2A52")
                ProgressView().tint(.white)
            }
        }
        .frame(width: Self.mapSize.width, height: Self.mapSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    /// Both of you close enough that one globe view, centered on your spherical midpoint, holds
    /// both pins at once — same sphere-fills-the-frame overscan crop `RelationshipStatsShareCard`
    /// uses, just with both pins drawn directly from the snapshot's own coordinate space since
    /// there's no off-globe geometry to reconcile against.
    private func normalGlobeContent(_ mapSnapshot: MKMapSnapshotter.Snapshot) -> some View {
        ZStack {
            // The sphere image + route, clipped to the circle — this layer alone, so a label
            // near the globe's edge (below) isn't cut off by that same circular mask even when
            // it's still safely inside the *outer* card.
            ZStack {
                Image(uiImage: mapSnapshot.image)
                    .resizable()
                    .scaledToFill()

                // Many short chords between closely-spaced great-circle samples — the same "many
                // short chords" trick `FlightMapView` uses for its route curve — rather than a
                // single line straight from pin to pin, which would cut the true geodesic arc.
                Path { path in
                    let sampleCount = 60
                    let samples = (0...sampleCount).map { i in
                        Geo.intermediateGreatCirclePoint(myCity.coordinate, partnerCity.coordinate, fraction: Double(i) / Double(sampleCount))
                    }
                    guard let first = samples.first else { return }
                    path.move(to: mapSnapshot.point(for: first))
                    for coordinate in samples.dropFirst() {
                        path.addLine(to: mapSnapshot.point(for: coordinate))
                    }
                }
                .stroke(Color(hex: "6FD3FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 11]))
            }
            .frame(width: Self.normalGlobeSize, height: Self.normalGlobeSize)
            .scaleEffect(Self.globeOverscan)
            .clipShape(Circle())
            .position(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2)

            // Pins get the identical scale+position transform (so they still land on the exact
            // spot the map layer projects their city to) but aren't clipped to the circle —
            // only the outer card's own rounded-rect bounds constrain them from here, via
            // `clampedGlobePoint` below (a plain `pin()`-internal clamp isn't enough, since that
            // one only knows about *pre-scale* local space, not the `globeOverscan` this whole
            // layer gets scaled by afterward).
            ZStack {
                pin(person: couple.partnerA, city: myCity, at: Self.clampedGlobePoint(mapSnapshot.point(for: myCity.coordinate)), boundsWidth: Self.normalGlobeSize)
                pin(person: couple.partnerB, city: partnerCity, at: Self.clampedGlobePoint(mapSnapshot.point(for: partnerCity.coordinate)), boundsWidth: Self.normalGlobeSize)
            }
            .frame(width: Self.normalGlobeSize, height: Self.normalGlobeSize)
            .scaleEffect(Self.globeOverscan)
            .position(x: Self.mapSize.width / 2, y: Self.mapSize.height / 2)
        }
    }

    /// Deliberately shrinks the outer card bounds *before* solving any of the margins below —
    /// those solve for a label touching the outer edge exactly, with zero slack for the card's
    /// own rounded corners or any small rounding in the constants they're built from, so a real
    /// pin could still graze the edge. Shaving a few points off the usable bounds up front
    /// applies the same safety margin to every derived value consistently.
    private static let edgeSafetyBuffer: CGFloat = 10

    /// Solves for the local-space x that keeps a scaled label pill's far edge exactly at the
    /// outer card's own edge, once this whole pin layer is scaled up by `globeOverscan` and
    /// repositioned at the card's center — `pin()`'s own bounds clamp alone doesn't know about
    /// that later transform, so a pin it considers safely inside can still land outside the card.
    private static let normalPinMargin: CGFloat = {
        let labelHalfWidth: CGFloat = 35
        let outerHalfWidth = mapSize.width / 2 - edgeSafetyBuffer
        let localHalfWidth = normalGlobeSize / 2
        let innerOuter = max(0, outerHalfWidth - labelHalfWidth * globeOverscan)
        return localHalfWidth - innerOuter / globeOverscan
    }()

    /// Same transform, solved separately for y — and asymmetrically, since the label sits
    /// `pinLabelOffset` *below* the pin rather than centered on it: the top bound only has to
    /// clear the avatar itself, while the bottom bound has to clear the avatar's own position
    /// *plus* that offset *plus* the label's half-height.
    private static let pinAvatarRadius: CGFloat = 16
    private static let pinLabelOffset: CGFloat = 30
    private static let pinLabelHalfHeight: CGFloat = 13

    /// The lowest local y whose avatar top edge still clears the outer card's top.
    private static let normalPinMinY: CGFloat = {
        let outerHalfHeight = mapSize.height / 2 - edgeSafetyBuffer
        let localCenter = normalGlobeSize / 2
        return localCenter - (outerHalfHeight - pinAvatarRadius * globeOverscan) / globeOverscan
    }()

    /// The highest local y whose label (offset below the pin) still clears the outer card's
    /// bottom.
    private static let normalPinMaxY: CGFloat = {
        let outerHalfHeight = mapSize.height / 2 - edgeSafetyBuffer
        let localCenter = normalGlobeSize / 2
        return localCenter - pinLabelOffset - pinLabelHalfHeight + outerHalfHeight / globeOverscan
    }()

    private static func clampedGlobePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, normalPinMargin), normalGlobeSize - normalPinMargin),
            y: min(max(point.y, normalPinMinY), normalPinMaxY)
        )
    }

    /// Too far apart for both to land on one cropped globe view — this one is centered on *your*
    /// city alone (so your pin sits at its center by construction), with the true initial
    /// bearing toward partner's city used to pick where the route exits the globe's edge, then
    /// curving on to a floating card for partner (their real city isn't on this smaller globe at
    /// all, so their card is its own element, not a projected map point).
    private func offGlobeContent(_ mapSnapshot: MKMapSnapshotter.Snapshot) -> some View {
        ZStack {
            ZStack {
                Image(uiImage: mapSnapshot.image)
                    .resizable()
                    .scaledToFill()
            }
            .frame(width: Self.offGlobeSize, height: Self.offGlobeSize)
            .scaleEffect(Self.globeOverscan)
            .clipShape(Circle())
            .position(Self.offGlobeCenter)

            // The segment from your pin to the globe's own edge starts *at* the circle's edge by
            // construction (a point exactly `offGlobeRadius` from its center), so it never needs
            // its own clip — then a curved segment continues on to partner's floating card.
            Path { path in
                path.move(to: Self.offGlobeCenter)
                path.addLine(to: offGlobeExitPoint)
            }
            .stroke(Color(hex: "6FD3FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 11]))

            offGlobeCurve

            pin(person: couple.partnerA, city: myCity, at: Self.offGlobeCenter, boundsWidth: Self.mapSize.width)
            floatingPartnerCard
        }
    }

    /// True initial great-circle bearing from your city toward partner's — converted from a
    /// compass heading (0° = north/up, clockwise) into the matching point on the globe's own
    /// rendered circle, so the exit point actually points the right way even though partner's
    /// city itself is off this smaller globe entirely.
    private var offGlobeExitPoint: CGPoint {
        let bearing = Geo.initialBearing(from: myCity.coordinate, to: partnerCity.coordinate) * .pi / 180
        return CGPoint(
            x: Self.offGlobeCenter.x + Self.offGlobeRadius * sin(bearing),
            y: Self.offGlobeCenter.y - Self.offGlobeRadius * cos(bearing)
        )
    }

    /// Bowed away from the globe (not a straight line into it) so it reads as a path curving
    /// around the sphere's surface out to partner, the same visual idea `RelationshipStatsCard`'s
    /// coupleHeader/`PassportView`'s flight path use for "two points, one connection," just
    /// arced here since the two ends aren't on the same straight line as the globe's center.
    private var offGlobeCurve: some View {
        let exit = offGlobeExitPoint
        let target = Self.floatingCardCenter
        let chordMid = CGPoint(x: (exit.x + target.x) / 2, y: (exit.y + target.y) / 2)
        let dx = target.x - exit.x, dy = target.y - exit.y
        let length = (dx * dx + dy * dy).squareRoot()
        let normal = length > 0 ? CGPoint(x: -dy / length, y: dx / length) : CGPoint(x: 0, y: -1)
        // Bows toward whichever side is farther from the globe's own center, so the curve
        // reads as arcing away from the sphere rather than doubling back across it.
        let towardOutside: CGFloat = ((chordMid.x - Self.offGlobeCenter.x) * normal.x + (chordMid.y - Self.offGlobeCenter.y) * normal.y) >= 0 ? 1 : -1
        let control = CGPoint(x: chordMid.x + normal.x * length * 0.35 * towardOutside, y: chordMid.y + normal.y * length * 0.35 * towardOutside)

        return Path { path in
            path.move(to: exit)
            path.addQuadCurve(to: target, control: control)
        }
        .stroke(Color(hex: "6FD3FF"), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 11]))
    }

    /// Partner's real city isn't visible on this smaller, you-centered globe — their card floats
    /// just outside its edge instead, still real (their actual avatar and city name), just not
    /// literally projected onto a map point the way the dual-pin view's pins are.
    private var floatingPartnerCard: some View {
        VStack(spacing: 6) {
            AvatarView(person: couple.partnerB, size: Self.pinAvatarRadius * 2, showsRing: true)
            Text(partnerCity.displayCity)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .position(Self.floatingCardCenter)
    }

    /// Anchored at the avatar's own center (not the label below it) so `point` — the real
    /// projected coordinate — is exactly where the pin visually sits, matching how a map pin's
    /// anchor works everywhere else in the app.
    private func pin(person: Person, city: Place, at point: CGPoint, boundsWidth: CGFloat) -> some View {
        // A fixed-width, single-line pill — city name alone is short enough that it doesn't
        // need to wrap, but a pin can still legitimately land near either edge of the map, so
        // the x position stays clamped inward by roughly half the pill's width to keep it from
        // running past that edge, at the cost of a small horizontal drift from the pin for edge
        // cases (the same trade-off real map apps make for edge-of-viewport labels).
        let labelWidth: CGFloat = 70
        let clampedX = min(max(point.x, labelWidth / 2 + 4), boundsWidth - labelWidth / 2 - 4)
        return Group {
            AvatarView(person: person, size: Self.pinAvatarRadius * 2, showsRing: true)
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
}

#Preview {
    DistanceShareCard(
        couple: MockData.couple,
        myCity: MockData.dara.homeCity ?? MockData.singapore,
        partnerCity: MockData.rosa.homeCity ?? MockData.melbourne,
        distanceKm: 6300,
        mapSnapshot: nil
    )
    .padding()
    .background(Color.black)
}
