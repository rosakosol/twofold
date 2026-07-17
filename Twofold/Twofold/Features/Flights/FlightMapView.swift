//
//  FlightMapView.swift
//  Twofold
//
//  Shared map used by both the Home active-flight card (compact) and the full flight detail
//  screen. Built directly on `MKMapView` (`UIViewRepresentable`) rather than SwiftUI's high-level
//  `Map` — three things needed that `Map` doesn't expose:
//    1. Screen-point edge padding when fitting the route (`setVisibleMapRect(_:edgePadding:)`),
//       which is what keeps the endpoint labels from being cropped near the frame's edge —
//       `Map`'s own coordinate-fraction-based region fitting can't reliably reserve pixel space
//       for a label sitting below a marker.
//    2. Native, uninterrupted pinch/pan: driving `Map` via a freshly-computed `initialPosition`
//       on every SwiftUI re-render (e.g. each time this flight's live-tracking data refreshes)
//       made the camera visibly snap back, which felt indistinguishable from "pinch doesn't
//       work." `MKMapView`'s own camera is untouched by SwiftUI body re-evaluations — this view
//       only ever calls into it explicitly (see `Coordinator.apply`), never resets it just
//       because the surrounding view redrew.
//    3. A live-follow camera for en-route flights (see `Coordinator.isFollowing`) that recenters
//       on the moving marker without resetting whatever zoom level the user last chose —
//       `setCenter(_:animated:)` alone, not a fresh region fit.
//

import MapKit
import SwiftUI
import UIKit

struct FlightMapView: View {
    @Environment(AppModel.self) private var appModel
    let flight: Flight
    var interactive: Bool = true
    /// Minimum padding (screen points) reserved around the fitted route on every edge, passed
    /// straight through to `MKMapView.setVisibleMapRect(_:edgePadding:animated:)`.
    var edgePadding: CGFloat = 40

    /// Resolved directly from the flight (set explicitly when adding it) rather than a linked
    /// trip — flights don't require one, so this is the only reliable source now. Can hold both
    /// partners when they're travelling together.
    private var travelers: [Person] {
        flight.travelerIDs.compactMap { appModel.couple.partner($0) }
    }

    var body: some View {
        // `.isFinite` alongside the nil-check — a NaN/infinite latitude or longitude (garbage
        // upstream data, not the normal "not resolved yet" case, which is nil and already
        // handled below) would otherwise flow straight into the camera-fitting math and crash
        // the map view outright.
        if let origin = flight.origin.coordinate, let destination = flight.destination.coordinate,
           origin.latitude.isFinite, origin.longitude.isFinite,
           destination.latitude.isFinite, destination.longitude.isFinite {
            MapKitRouteView(
                origin: origin,
                destination: destination,
                originCode: flight.origin.displayCode,
                destinationCode: flight.destination.displayCode,
                position: flight.positionCoordinate,
                positionHeading: flight.positionHeading,
                travelers: travelers,
                currentUserID: appModel.currentUser.id,
                bestDeparture: flight.bestDeparture,
                bestArrival: flight.bestArrival,
                status: flight.status,
                interactive: interactive,
                // Only the full detail screen (interactive) gets the immersive live-follow
                // camera when en route — the compact Home card is a glanceable route overview,
                // and it's non-interactive anyway so a user could never pinch back out of a tight
                // follow zoom there.
                followWhenEnRoute: interactive,
                edgePadding: edgePadding
            )
        } else {
            fallback
        }
    }

    /// Scheduled flights (or self-reported ones) may not have airport coordinates yet — a
    /// calm placeholder rather than an empty map or a crash.
    private var fallback: some View {
        ZStack {
            Theme.cardBackground
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(Theme.subtleInk)
                Text("Map will appear once route data is available")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }
        }
    }
}

/// The `MKMapView` itself. A thin `UIViewRepresentable` shell — all the real work (building the
/// route overlays, placing annotations, fitting/following the camera) happens in `Coordinator`,
/// which persists across SwiftUI body re-evaluations exactly like the underlying `MKMapView` does.
private struct MapKitRouteView: UIViewRepresentable {
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let originCode: String
    let destinationCode: String
    let position: CLLocationCoordinate2D?
    let positionHeading: Double?
    /// 0, 1, or 2 people — both partners can be marked as travelling together on one flight.
    let travelers: [Person]
    /// Whose device this is — when both partners are travelling together, the marker keeps
    /// `travelers`' own left/right layout order but draws this person's avatar on top (see
    /// `Coordinator.bothTravelersMarker`), rather than repositioning it.
    let currentUserID: Person.ID?
    /// Raw times, not a pre-computed progress fraction — the Coordinator recomputes "how far
    /// along the route" itself, live, on every animation tick (see `Coordinator.liveProgress`),
    /// so the marker keeps moving smoothly between polls instead of only jumping once per
    /// SwiftUI re-render (which only happens when this flight's underlying data actually changes,
    /// every few minutes at best).
    let bestDeparture: Date?
    let bestArrival: Date?
    let status: FlightStatus
    let interactive: Bool
    let followWhenEnRoute: Bool
    let edgePadding: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SizeAwareMapView {
        let mapView = SizeAwareMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isZoomEnabled = interactive
        mapView.isScrollEnabled = interactive
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        // `MKMapView` ships with a non-nil default `cameraZoomRange`, and re-assigning `nil`
        // doesn't clear it (reading it back immediately afterward still shows a non-nil value) —
        // an explicit, generous max distance here guards against it constraining `fitCamera`'s
        // `MKMapCamera`-based fit (see that function's comment for the actual root cause of why
        // region-based fitting doesn't work for a wide route in the first place).
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: 40_000_000)
        context.coordinator.mapView = mapView
        // `makeUIView` runs before SwiftUI has laid the view out, so `mapView.bounds` is still
        // zero here — fitting the camera against a zero-sized view produces a garbage zoom level
        // (this was the actual cause of "ports cropped out of view": the very first fit landed on
        // whatever degenerate span a zero-width/height rect implies). `onLayout` below catches the
        // real size once UIKit actually lays the view out and (re)runs the deferred fit then.
        mapView.onLayout = { [weak mapView, weak coordinator = context.coordinator] in
            guard let mapView, let coordinator else { return }
            coordinator.layoutDidChange(mapView: mapView)
        }
        context.coordinator.apply(route(), edgePadding: edgePadding, followWhenEnRoute: followWhenEnRoute)
        return mapView
    }

    func updateUIView(_ mapView: SizeAwareMapView, context: Context) {
        context.coordinator.apply(route(), edgePadding: edgePadding, followWhenEnRoute: followWhenEnRoute)
    }

    private func route() -> Coordinator.Route {
        Coordinator.Route(
            origin: origin,
            destination: destination,
            originCode: originCode,
            destinationCode: destinationCode,
            position: position,
            positionHeading: positionHeading,
            travelers: travelers,
            currentUserID: currentUserID,
            bestDeparture: bestDeparture,
            bestArrival: bestArrival,
            status: status
        )
    }

    /// Owns the `MKMapView` delegate callbacks, the route overlays, and the three annotations
    /// (origin, destination, live/traveler position) — plus the follow-camera state machine for
    /// en-route flights.
    final class Coordinator: NSObject, MKMapViewDelegate {
        struct Route: Equatable {
            var origin: CLLocationCoordinate2D
            var destination: CLLocationCoordinate2D
            var originCode: String
            var destinationCode: String
            var position: CLLocationCoordinate2D?
            var positionHeading: Double?
            var travelers: [Person]
            var currentUserID: Person.ID?
            var bestDeparture: Date?
            var bestArrival: Date?
            var status: FlightStatus

            static func == (lhs: Route, rhs: Route) -> Bool {
                lhs.origin.latitude == rhs.origin.latitude && lhs.origin.longitude == rhs.origin.longitude
                    && lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
                    && lhs.originCode == rhs.originCode && lhs.destinationCode == rhs.destinationCode
                    && lhs.position?.latitude == rhs.position?.latitude && lhs.position?.longitude == rhs.position?.longitude
                    && lhs.positionHeading == rhs.positionHeading && lhs.travelers.map(\.id) == rhs.travelers.map(\.id)
                    && lhs.currentUserID == rhs.currentUserID
                    && lhs.bestDeparture == rhs.bestDeparture && lhs.bestArrival == rhs.bestArrival && lhs.status == rhs.status
            }
        }

        private static let originIdentifier = "flight-origin"
        private static let destinationIdentifier = "flight-destination"
        private static let positionIdentifier = "flight-position"

        weak var mapView: MKMapView?

        private var hasFittedCamera = false
        /// Once true, the camera recenters on the marker as it moves without touching zoom —
        /// turned off the moment the user manually pans/pinches (see
        /// `mapView(_:regionDidChangeAnimated:)`), so it never fights a deliberate gesture.
        private var isFollowing = false
        /// Guards `regionDidChangeAnimated` from mistaking our own programmatic camera calls
        /// (`setVisibleMapRect`/`setRegion`/`setCenter`) for user-driven ones — set immediately
        /// before each such call, consumed on the very next delegate callback.
        private var isProgrammaticCameraChange = false
        private var lastAppliedRoute: Route?

        private var originAnnotation: RouteAnnotation?
        private var destinationAnnotation: RouteAnnotation?
        private var positionAnnotation: RouteAnnotation?
        private var originHasOverlappingMarker = false
        private var destinationHasOverlappingMarker = false

        /// Drives the marker (and, while en route, the follow camera) continuously between polls
        /// — `apply`/`layoutDidChange` only ever fire when this flight's underlying data actually
        /// changes or the view relays out, which without this left the plane/avatar sitting
        /// frozen in place for however long the last poll interval was, then visibly snapping to
        /// its new spot on the next update instead of having appeared to fly there. Started once
        /// `mapView` is known (see `apply`) and invalidated in `deinit`; each tick is a no-op
        /// unless the flight is actually between departure and arrival (see `tick`), so it isn't
        /// spending anything on a flight that's scheduled or already landed.
        private var animationTimer: Timer?

        deinit {
            animationTimer?.invalidate()
        }

        /// The most recent values passed to `apply` — replayed by `layoutDidChange` if the very
        /// first fit had to be deferred because the view wasn't laid out yet, or if the view's
        /// real size later turns out to differ from what it was fitted against.
        private var pendingEdgePadding: CGFloat = 40
        private var pendingFollowWhenEnRoute = false
        /// The `MKMapView` bounds size the last fit was computed against — `layoutSubviews` fires
        /// on every relayout, not just the first one, and a card living inside a
        /// `ScrollView`/`containerRelativeFrame` carousel (the Home flight carousel) can settle
        /// through more than one width before reaching its final size. Comparing against this
        /// lets `layoutDidChange` tell "just another relayout at the same size" (ignore) apart
        /// from "the container actually resized since we last fitted" (refit) — without it, a fit
        /// computed against an early, too-narrow intermediate width stuck permanently, which is
        /// what made the Home card's route look wrong/never-corrected.
        private var lastFittedBoundsSize: CGSize = .zero

        /// 0...1, computed fresh from wall-clock time on every call (mirrors `Flight.progress`'s
        /// own formula) rather than trusting a value baked in at the last SwiftUI re-render —
        /// re-render only happens when this flight's underlying data actually changes (a poll,
        /// every couple of minutes at best), which is what made the plane/avatar marker sit
        /// frozen between updates instead of visibly advancing along the route in real time.
        private static func liveProgress(for route: Route) -> Double {
            guard let departure = route.bestDeparture, let arrival = route.bestArrival, arrival > departure else {
                return route.status == .arrived || route.status == .landed ? 1 : 0
            }
            let elapsed = Date.now.timeIntervalSince(departure)
            let total = arrival.timeIntervalSince(departure)
            return min(1, max(0, elapsed / total))
        }

        /// Flighty-style close tracking: statuses where the plane is genuinely airborne and its
        /// live position is worth zooming in on. Excludes `.boarding` (still at the gate — the
        /// marker just sits on the origin, nothing to zoom into yet).
        private static func isFollowEligible(_ status: FlightStatus) -> Bool {
            status == .departed || status == .inAir || status == .landingSoon
        }

        func apply(_ route: Route, edgePadding: CGFloat, followWhenEnRoute: Bool) {
            guard let mapView else { return }
            pendingEdgePadding = edgePadding
            pendingFollowWhenEnRoute = followWhenEnRoute
            startAnimationTimerIfNeeded()

            guard route != lastAppliedRoute else { return }

            let previousStatus = lastAppliedRoute?.status
            updateOverlays(route, mapView: mapView)
            lastAppliedRoute = route

            let wasFollowEligible = previousStatus.map(Self.isFollowEligible) ?? false
            let isFollowEligible = Self.isFollowEligible(route.status)
            let enteredEnRoute = followWhenEnRoute && isFollowEligible && !wasFollowEligible
            let leftEnRoute = followWhenEnRoute && !isFollowEligible && wasFollowEligible
            guard !hasFittedCamera || enteredEnRoute || leftEnRoute else {
                // The camera's already been fitted at least once, so it's safe to touch
                // annotations here too (see `updateAnnotations`).
                updateAnnotations(route, mapView: mapView)
                if isFollowing, let marker = markerCoordinate(for: route) {
                    isProgrammaticCameraChange = true
                    mapView.setCenter(marker, animated: true)
                }
                return
            }

            // A zero-sized view can't be fitted meaningfully — `layoutDidChange` retries once
            // UIKit actually lays it out, so `hasFittedCamera` stays false here rather than
            // getting marked done against a bogus size. Annotations wait too (see
            // `updateAnnotations`'s doc comment) — added now, they'd position themselves against
            // this not-yet-fitted camera and never get corrected.
            guard mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }
            // Never animated — an animated `setVisibleMapRect` reads back its *starting* region
            // (not the target) from `visibleMapRect`/annotation positions until the animation
            // actually finishes, which given how often this can re-run (e.g. the carousel's
            // container settling to its final width across a couple of layout passes) meant a
            // later, correctly-computed fit could visually appear to do nothing or look wrong for
            // the ~0.3s the previous animation was still mid-flight.
            fitCamera(for: route, edgePadding: edgePadding, followWhenEnRoute: followWhenEnRoute, mapView: mapView, animated: false)
            hasFittedCamera = true
            lastFittedBoundsSize = mapView.bounds.size
            isFollowing = followWhenEnRoute && isFollowEligible
            updateAnnotations(route, mapView: mapView)
        }

        /// Fires on every `layoutSubviews` of the underlying `MKMapView` — re-fits whenever
        /// there's been no fit yet, or the view's real size has meaningfully changed since the
        /// last one (see `lastFittedBoundsSize`); otherwise a no-op.
        func layoutDidChange(mapView: MKMapView) {
            guard let route = lastAppliedRoute, mapView.bounds.width > 1, mapView.bounds.height > 1 else { return }
            let currentSize = mapView.bounds.size
            let sizeChanged = abs(currentSize.width - lastFittedBoundsSize.width) > 2 || abs(currentSize.height - lastFittedBoundsSize.height) > 2
            guard !hasFittedCamera || sizeChanged else { return }
            fitCamera(for: route, edgePadding: pendingEdgePadding, followWhenEnRoute: pendingFollowWhenEnRoute, mapView: mapView, animated: false)
            hasFittedCamera = true
            lastFittedBoundsSize = currentSize
            isFollowing = pendingFollowWhenEnRoute && Self.isFollowEligible(route.status)
            updateAnnotations(route, mapView: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isProgrammaticCameraChange {
                isProgrammaticCameraChange = false
                return
            }
            // A real pinch/pan from the user — let them keep it; stop overriding their view with
            // follow-camera recenters until the flight's en-route state changes again.
            isFollowing = false
        }

        // MARK: - Continuous animation

        /// Both the timer's firing interval and the duration of each `UIView.animate` step in
        /// `updatePositionAnnotation` — keeping them equal is what makes the motion continuous:
        /// each animated hop finishes exactly as the next tick starts a new one, instead of
        /// pausing (interval > duration, a stutter) or overlapping (interval < duration, a snap
        /// mid-flight as a new animation interrupts the one still running).
        private static let animationTickInterval: TimeInterval = 1

        private func startAnimationTimerIfNeeded() {
            guard animationTimer == nil else { return }
            let timer = Timer(timeInterval: Self.animationTickInterval, repeats: true) { [weak self] _ in
                self?.tick()
            }
            // `.common` (not the default `.default` run loop mode) so this keeps firing while
            // the user is actively touching the map — e.g. mid-pinch/pan — rather than pausing
            // for however long their gesture lasts.
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        }

        /// Once a second: re-renders the route/marker at whatever `liveProgress` is *right now*,
        /// and — while following an en-route flight — recenters the camera on it, all without
        /// waiting for `apply` to be called again by a fresh poll. A no-op whenever the flight
        /// isn't actually between departure and arrival, so a scheduled or already-landed flight
        /// isn't burning a tick on a marker that was never going to move anyway.
        private func tick() {
            guard let mapView, let route = lastAppliedRoute, hasFittedCamera else { return }
            let progress = Self.liveProgress(for: route)
            guard progress > 0.001, progress < 0.999 else { return }

            updateOverlays(route, mapView: mapView)
            updateAnnotations(route, mapView: mapView, animate: true)
            if isFollowing, let marker = markerCoordinate(for: route) {
                isProgrammaticCameraChange = true
                // `animated: false` inside an explicit `UIView.animate` block, not MapKit's own
                // `animated: true` — that used a fixed system duration/curve MapKit doesn't expose
                // for tuning, which finished in well under a second and then sat still until the
                // next tick's recenter, reading as a camera that snaps hard once a second rather
                // than tracking the marker. Matching the duration and linear curve to the marker's
                // own glide (`updatePositionAnnotation`) keeps the camera arriving exactly when the
                // marker does, so the two move together instead of camera-snap-then-pause.
                UIView.animate(withDuration: Self.animationTickInterval, delay: 0, options: [.curveLinear]) {
                    mapView.setCenter(marker, animated: false)
                }
            }
        }

        // MARK: - Camera

        /// Tight zoom on the live marker for an en-route flight, close enough that the
        /// plane/avatar's motion between successive position updates is clearly visible against
        /// nearby geography (roads, towns) — matching the close-tracking view flight-tracking
        /// apps like Flighty use, rather than a wide regional overview.
        private static let followSpanMeters: CLLocationDistance = 25_000

        private func fitCamera(for route: Route, edgePadding: CGFloat, followWhenEnRoute: Bool, mapView: MKMapView, animated: Bool) {
            isProgrammaticCameraChange = true
            if followWhenEnRoute, Self.isFollowEligible(route.status), let marker = markerCoordinate(for: route) {
                mapView.setRegion(MKCoordinateRegion(center: marker, latitudinalMeters: Self.followSpanMeters, longitudinalMeters: Self.followSpanMeters), animated: animated)
                return
            }

            // Endpoint labels hang below their coordinate, not around it symmetrically (see
            // `endpointMarker`/`endpointMarkerSize`) — whichever endpoint lands at the bottom of
            // the fitted route needs that much extra clearance below it, or its label gets
            // clipped by the card's edge instead of just sitting there unread. Based on the
            // marker's actual current overlap state (usually smaller than the worst case) rather
            // than always assuming a traveler avatar is parked on that endpoint — reserving the
            // full worst-case clearance unconditionally was eating nearly a third of the Home
            // card's short 140pt height, forcing the whole route to zoom out far more than
            // necessary just to leave room for a label overlap that, most of the time, isn't
            // actually happening.
            let hasOverlap = markerOverlapsEndpoint(for: route)
            let markerSize = Self.endpointMarkerSize(hasOverlappingMarker: hasOverlap)
            let labelClearance = markerSize.height - 5
            // The label capsule is centered under the dot and wider than the base edge padding
            // alone accounts for — whichever endpoint lands near the *left or right* edge (common
            // for a route that crosses mostly east-west, like an ocean-spanning one, rather than
            // pole-to-pole) needs that half-width reserved too, or the capsule clips off the side
            // instead of just the bottom.
            let horizontalClearance = max(edgePadding, markerSize.width / 2)
            let insets = UIEdgeInsets(top: edgePadding, left: horizontalClearance, bottom: edgePadding + labelClearance, right: horizontalClearance)

            // `MKCoordinateRegion`-based fitting (`setRegion`/`setVisibleMapRect`/`showAnnotations`
            // — all three tried) silently caps how wide a region's *span in degrees* can be at a
            // given center latitude, well short of what a route like this genuinely needs — empty
            // ocean got zoomed into instead of the actual route, no matter how much padding or
            // extra span was requested. `MKMapCamera(lookingAtCenter:fromDistance:)` sets the
            // camera by altitude instead of a coordinate span, which isn't subject to that same
            // ceiling, so this fits the *whole* curve (not just the two ports) — including its
            // high-latitude peak (e.g. ~62°N for a Shanghai–Dallas polar great circle) — via the
            // same empirical grow-until-it-fits loop, driven through the camera API instead.
            let samples = Self.routeSamples(from: route.origin, to: route.destination)
            let points = Self.unwrappedMapPoints(for: samples)
            let worldWidth = MKMapSize.world.width
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            var midX = (minX + maxX) / 2
            if midX < 0 { midX += worldWidth }
            if midX >= worldWidth { midX -= worldWidth }
            let center = MKMapPoint(x: midX, y: (minY + maxY) / 2).coordinate
            let metersPerMapPoint = MKMetersPerMapPointAtLatitude(center.latitude)
            let minSpanMapPoints = 2_000.0
            let spanMeters = max(max(maxY - minY, minSpanMapPoints), max(maxX - minX, minSpanMapPoints)) * metersPerMapPoint
            let safeMinX = insets.left, safeMinY = insets.top
            let safeMaxX = mapView.bounds.width - insets.right, safeMaxY = mapView.bounds.height - insets.bottom

            let maxDistance: CLLocationDistance = 30_000_000
            var distance: CLLocationDistance = min(spanMeters * 2.4, maxDistance)
            for attempt in 0..<10 {
                mapView.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: 0), animated: animated && attempt == 0)
                let fits = samples.allSatisfy { sample in
                    let p = mapView.convert(sample, toPointTo: mapView)
                    return p.x >= safeMinX && p.x <= safeMaxX && p.y >= safeMinY && p.y <= safeMaxY
                }
                if fits { break }
                distance = min(distance * 1.4, maxDistance)
            }
        }

        private func markerOverlapsEndpoint(for route: Route) -> Bool {
            guard let marker = markerCoordinate(for: route) else { return false }
            let originOverlap = marker.latitude == route.origin.latitude && marker.longitude == route.origin.longitude
            let destinationOverlap = marker.latitude == route.destination.latitude && marker.longitude == route.destination.longitude
            return originOverlap || destinationOverlap
        }

        // MARK: - Building the route

        /// Endpoint and position annotation views — `MKAnnotationView` positions itself once,
        /// against whatever camera is active the moment `viewFor` runs for it; adding one before
        /// the map has ever had a real camera fit applied left it stuck rendered at a degenerate
        /// off-screen position that MapKit never corrected afterward once the camera later became
        /// valid (unlike overlays, which redraw fresh every frame regardless of when they were
        /// added — see `updateOverlays`, safe to call anytime). Callers only invoke this once
        /// `hasFittedCamera` is true.
        private func updateAnnotations(_ route: Route, mapView: MKMapView, animate: Bool = false) {
            updateEndpointAnnotations(route, mapView: mapView)
            updatePositionAnnotation(route, mapView: mapView, animate: animate)
        }

        /// Traveled portion (origin up to the flight's current progress) vs. the leg not yet
        /// flown — same hue, so the line still reads as one continuous route, just with the
        /// traveled part vivid and the rest faded back, rather than the two-color progress-
        /// gradient banding tried earlier (visually busy, and its per-segment color bands didn't
        /// line up with the real progress closely enough to read as meaningful).
        private static let traveledColor = UIColor(red: 0.10, green: 0.48, blue: 1.0, alpha: 1.0)
        private static let untraveledColor = UIColor(red: 0.10, green: 0.48, blue: 1.0, alpha: 0.35)

        private func updateOverlays(_ route: Route, mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)

            // Manually sampled points (`routeSamples`/`unwrappedMapPoints` — the same ones
            // `fitCamera` uses for its own distance math), not `MKGeodesicPolyline` — tried that
            // first since it hands the curve math to MapKit, but its adaptive point insertion
            // turned out to be noticeably *sparser* than this manual sampling, leaving a visible
            // facet right at the peak of a long-haul arc (e.g. Seattle–Barcelona) that this
            // denser sampling doesn't show. Building the casing from this exact same points array
            // (not a separately-constructed line) also guarantees it traces exactly under the
            // colored line — no separate curve computation to drift apart from it.
            let points = Self.unwrappedMapPoints(for: Self.routeSamples(from: route.origin, to: route.destination))
            let casing = ColoredPolyline(points: points, count: points.count)
            casing.strokeColor = .white
            casing.lineWidth = 7
            mapView.addOverlay(casing)

            let progress = route.status == .diverted ? 0 : Self.liveProgress(for: route)
            let (traveled, untraveled) = Self.splitPoints(points, progress: progress)
            if !untraveled.isEmpty {
                let line = ColoredPolyline(points: untraveled, count: untraveled.count)
                line.strokeColor = Self.untraveledColor
                line.lineWidth = 4
                mapView.addOverlay(line)
            }
            if !traveled.isEmpty {
                let line = ColoredPolyline(points: traveled, count: traveled.count)
                line.strokeColor = Self.traveledColor
                line.lineWidth = 4
                mapView.addOverlay(line)
            }
        }

        /// Splits the evenly-spaced route samples into a traveled prefix and untraveled suffix at
        /// `progress`, linearly interpolating the exact split point between the two samples it
        /// falls between so the two polylines meet without a visible gap or overlap.
        private static func splitPoints(_ points: [MKMapPoint], progress: Double) -> (traveled: [MKMapPoint], untraveled: [MKMapPoint]) {
            guard points.count > 1 else { return (points, points) }
            if progress <= 0.001 { return ([], points) }
            if progress >= 0.999 { return (points, []) }

            let totalSegments = points.count - 1
            let exactIndex = progress * Double(totalSegments)
            let splitIndex = min(max(Int(exactIndex), 0), totalSegments - 1)
            let fraction = exactIndex - Double(splitIndex)
            let a = points[splitIndex], b = points[splitIndex + 1]
            let splitPoint = MKMapPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)

            var traveled = Array(points[0...splitIndex])
            traveled.append(splitPoint)
            var untraveled = [splitPoint]
            untraveled.append(contentsOf: points[(splitIndex + 1)...])
            return (traveled, untraveled)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let colored = overlay as? ColoredPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: colored)
            renderer.strokeColor = colored.strokeColor
            renderer.lineWidth = colored.lineWidth
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? RouteAnnotation else { return nil }
            let identifier = annotation.reuseIdentifier
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SwiftUIAnnotationView
                ?? SwiftUIAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            switch annotation.kind {
            case .origin, .destination:
                // Anchored so the dot (not the whole dot+label stack) sits on the true
                // coordinate. When a traveler avatar is parked on this exact point (pre-
                // departure — see `updatePositionAnnotation`), the label is pushed down far
                // enough to clear it and stay legible underneath; otherwise it sits close to the
                // dot like an ordinary caption, since there's nothing to clear.
                let size = Self.endpointMarkerSize(hasOverlappingMarker: annotation.hasOverlappingMarker)
                view.setContent(
                    Self.endpointMarker(code: annotation.title ?? "", hasOverlappingMarker: annotation.hasOverlappingMarker),
                    size: size,
                    centerOffset: CGPoint(x: 0, y: size.height / 2 - 5)
                )
                // Below the live position marker in z-order (set explicitly below) — when they
                // coincide (pre-departure or just after arrival), the plane/avatar is the more
                // important thing to actually see, not the plain endpoint dot underneath it.
                view.zPriority = .init(rawValue: 1)
            case .position:
                switch annotation.travelers.count {
                case 0:
                    view.setContent(Self.planeMarker(heading: annotation.positionHeading), size: CGSize(width: 30, height: 30))
                case 1:
                    view.setContent(Self.travelerMarker(annotation.travelers[0]), size: CGSize(width: 44, height: 44))
                default:
                    view.setContent(Self.bothTravelersMarker(annotation.travelers, currentUserID: annotation.currentUserID), size: CGSize(width: 56, height: 44))
                }
                view.zPriority = .init(rawValue: 2)
            }
            return view
        }

        /// Diverted is the one exception: the plane is no longer following the original
        /// origin-destination line at all, so a progress-interpolated point along it would be
        /// actively misleading. Falls back to the real live position there, or the origin if no
        /// position has ever been reported.
        private func markerCoordinate(for route: Route) -> CLLocationCoordinate2D? {
            if route.status == .diverted { return route.position ?? route.origin }
            let progress = Self.liveProgress(for: route)
            if progress <= 0.001 { return route.origin }
            if progress >= 0.999 { return route.destination }
            return Self.intermediateGreatCirclePoint(route.origin, route.destination, fraction: progress)
        }

        private func updateEndpointAnnotations(_ route: Route, mapView: MKMapView) {
            let marker = markerCoordinate(for: route)
            let originOverlap = marker.map { $0.latitude == route.origin.latitude && $0.longitude == route.origin.longitude } ?? false
            let destinationOverlap = marker.map { $0.latitude == route.destination.latitude && $0.longitude == route.destination.longitude } ?? false

            if originAnnotation == nil || originHasOverlappingMarker != originOverlap {
                if let existing = originAnnotation { mapView.removeAnnotation(existing) }
                let annotation = RouteAnnotation(kind: .origin, reuseIdentifier: Self.originIdentifier)
                annotation.coordinate = route.origin
                annotation.title = route.originCode
                annotation.hasOverlappingMarker = originOverlap
                mapView.addAnnotation(annotation)
                originAnnotation = annotation
                originHasOverlappingMarker = originOverlap
            }
            if destinationAnnotation == nil || destinationHasOverlappingMarker != destinationOverlap {
                if let existing = destinationAnnotation { mapView.removeAnnotation(existing) }
                let annotation = RouteAnnotation(kind: .destination, reuseIdentifier: Self.destinationIdentifier)
                annotation.coordinate = route.destination
                annotation.title = route.destinationCode
                annotation.hasOverlappingMarker = destinationOverlap
                mapView.addAnnotation(annotation)
                destinationAnnotation = annotation
                destinationHasOverlappingMarker = destinationOverlap
            }
        }

        /// Before departure there's no live position from the provider yet, but the marker still
        /// rides the route — parked at the origin — rather than only appearing once the flight is
        /// airborne. That's true whether it's a traveler's avatar or the plane-icon fallback (no
        /// traveler set): both are driven by `progress`, not the raw live GPS ping (see
        /// `markerCoordinate(for:)`), so there's always something to show once a route exists.
        ///
        /// `animate: true` (used by the once-a-second animation tick) mutates the *existing*
        /// annotation's coordinate inside a `UIView.animate` block instead of removing and
        /// re-adding it — `MKPointAnnotation.coordinate` is KVO-observed by the map view's own
        /// positioning, so wrapping the change in an animation block is what actually makes
        /// MapKit interpolate the marker smoothly between the old and new spot over that second,
        /// rather than teleporting there the instant this runs. Remove-and-re-add is still used
        /// for every other case (first placement, a traveler being added/removed, or any
        /// non-animated call) — those genuinely are a different marker, not a continuation of the
        /// same one moving.
        private func updatePositionAnnotation(_ route: Route, mapView: MKMapView, animate: Bool = false) {
            guard let coordinate = markerCoordinate(for: route) else {
                if let existing = positionAnnotation {
                    mapView.removeAnnotation(existing)
                    positionAnnotation = nil
                }
                return
            }
            let heading = Self.markerHeading(for: route, at: coordinate)

            if animate, let existing = positionAnnotation, existing.travelers.map(\.id) == route.travelers.map(\.id) {
                existing.positionHeading = heading
                UIView.animate(withDuration: Self.animationTickInterval, delay: 0, options: [.curveLinear]) {
                    existing.coordinate = coordinate
                }
                // The plane icon's heading-based rotation is the one bit of the hosted SwiftUI
                // content that can change tick-to-tick even without a traveler/plane switch —
                // refreshed in place (not via remove/re-add) and wrapped in the same animation
                // duration so it turns smoothly alongside the move instead of snapping.
                if route.travelers.isEmpty, let view = mapView.view(for: existing) as? SwiftUIAnnotationView {
                    withAnimation(.linear(duration: Self.animationTickInterval)) {
                        view.setContent(Self.planeMarker(heading: heading), size: CGSize(width: 30, height: 30))
                    }
                }
                return
            }

            if let existing = positionAnnotation {
                mapView.removeAnnotation(existing)
                positionAnnotation = nil
            }
            let annotation = RouteAnnotation(kind: .position, reuseIdentifier: Self.positionIdentifier)
            annotation.coordinate = coordinate
            annotation.positionHeading = heading
            annotation.travelers = route.travelers
            annotation.currentUserID = route.currentUserID
            mapView.addAnnotation(annotation)
            positionAnnotation = annotation
        }

        // MARK: - Marker content (SwiftUI, hosted via SwiftUIAnnotationView)

        /// Total size of an endpoint's dot+label content — fixed (rather than left to SwiftUI's
        /// own sizing) so the centering math in `viewFor annotation:` above can be computed
        /// exactly instead of guessed. When a traveler avatar is parked on the same coordinate
        /// (44pt, radius 22pt), the gap between dot and label widens enough to clear it with
        /// margin to spare; otherwise the label sits close to the dot like an ordinary caption.
        private static func endpointMarkerSize(hasOverlappingMarker: Bool) -> CGSize {
            CGSize(width: 56, height: hasOverlappingMarker ? 50 : 34)
        }

        private static func endpointMarker(code: String, hasOverlappingMarker: Bool) -> some View {
            let size = endpointMarkerSize(hasOverlappingMarker: hasOverlappingMarker)
            return VStack(spacing: hasOverlappingMarker ? 20 : 6) {
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                Text(code)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }

        /// Bigger than the plane marker — this is the whole point of knowing who's on the
        /// flight, so it should read clearly at a glance rather than blend in with the route.
        private static func travelerMarker(_ person: Person) -> some View {
            AvatarView(person: person, size: 44, showsRing: true)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }

        /// Both partners travelling together — two smaller avatars overlapping rather than one
        /// 44pt avatar per person, so the marker doesn't balloon in size or obscure the route
        /// underneath it. `HStack`'s paint order normally follows its layout order (later =
        /// further right = drawn on top), which would force whoever's on-screen right to also be
        /// the one in front — `.zIndex` decouples the two, so the current device's own person can
        /// stay wherever `people` naturally puts them left-to-right while still drawing on top of
        /// their partner.
        private static func bothTravelersMarker(_ people: [Person], currentUserID: Person.ID?) -> some View {
            HStack(spacing: -14) {
                ForEach(people) { person in
                    AvatarView(person: person, size: 34, showsRing: true)
                        .zIndex(person.id == currentUserID ? 1 : 0)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
        }

        private static func planeMarker(heading: Double?) -> some View {
            ZStack {
                Circle().fill(Theme.skyBlue)
                Image(systemName: "airplane")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    // SF Symbols' "airplane" glyph points due east (right) at rotation 0 —
                    // verified by rendering it at several rotations and comparing, since the
                    // commonly-assumed "points ~45° NE at rotation 0" turned out to be wrong.
                    // `.rotationEffect` turns clockwise for positive degrees, and `heading` is a
                    // compass bearing (0 = north, 90 = east, clockwise) — since the glyph's rest
                    // orientation (east) is already bearing 90, the rotation needed to reach
                    // `heading` is `heading - 90`, not `90 - heading` (which mirrors every
                    // heading except due east/west, e.g. sends a northbound plane pointing south).
                    .rotationEffect(.degrees((heading ?? 0) - 90))
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
        }

        // MARK: - Great-circle route sampling

        /// A point along the great-circle path between `a` and `b` at fraction `f` (0 = a, 1 =
        /// b) — the standard "intermediate point on a great circle" formula. Needed because the
        /// route's true curve can bulge significantly away from the straight line between the
        /// endpoints, especially for long east-west routes at mid/high latitudes (which bow
        /// toward the pole — e.g. Hong Kong to Los Angeles peaks up near the Aleutians, well
        /// north of either endpoint). Sampling the curve (not just its two endpoints) keeps both
        /// the drawn line and the camera-fitting bounds honest to the route's real shape.
        private static func intermediateGreatCirclePoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, fraction f: Double) -> CLLocationCoordinate2D {
            let φ1 = a.latitude * .pi / 180, λ1 = a.longitude * .pi / 180
            let φ2 = b.latitude * .pi / 180, λ2 = b.longitude * .pi / 180

            let sinΔφ = sin((φ2 - φ1) / 2)
            let sinΔλ = sin((λ2 - λ1) / 2)
            let h = sinΔφ * sinΔφ + cos(φ1) * cos(φ2) * sinΔλ * sinΔλ
            let δ = 2 * asin(min(1, sqrt(h)))
            guard δ > 0.0000001 else { return a }

            let A = sin((1 - f) * δ) / sin(δ)
            let B = sin(f * δ) / sin(δ)
            let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
            let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
            let z = A * sin(φ1) + B * sin(φ2)
            let φi = atan2(z, sqrt(x * x + y * y))
            let λi = atan2(y, x)
            return CLLocationCoordinate2D(latitude: φi * 180 / .pi, longitude: λi * 180 / .pi)
        }

        /// The plane-icon fallback's nose direction — the great-circle forward bearing from the
        /// marker's current (progress-interpolated) position toward the destination, in degrees
        /// clockwise from north. A great circle's bearing isn't constant along its length (that's
        /// why it draws as a curve, not a straight line), so this is recomputed from wherever the
        /// marker actually is, not just once from origin to destination.
        ///
        /// Diverted is the exception: the plane isn't heading toward the original destination
        /// anymore, so the real live ADS-B heading (if any) is the honest answer there instead.
        /// Right at the destination coordinate the bearing calculation degenerates (Δ ≈ 0), so
        /// that case falls back to the live heading too — cosmetic only, since the marker isn't
        /// moving anymore at that point regardless of which way it's pointing.
        private static func markerHeading(for route: Route, at coordinate: CLLocationCoordinate2D) -> Double? {
            if route.status == .diverted { return route.positionHeading }
            if coordinate.latitude == route.destination.latitude && coordinate.longitude == route.destination.longitude {
                return route.positionHeading
            }
            return bearing(from: coordinate, to: route.destination)
        }

        /// Standard forward-azimuth formula — the initial bearing (degrees clockwise from north,
        /// 0..<360) of the great-circle path from `a` toward `b`.
        private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
            let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
            let Δλ = (b.longitude - a.longitude) * .pi / 180
            let y = sin(Δλ) * cos(φ2)
            let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
            let θ = atan2(y, x) * 180 / .pi
            return θ.truncatingRemainder(dividingBy: 360) + (θ < 0 ? 360 : 0)
        }

        /// Samples 1500 points along the great-circle curve (plus both endpoints) — dense enough
        /// that the short straight segments between consecutive samples read as a genuinely
        /// smooth curve rather than a faceted polyline even at the wide, zoomed-out framing the
        /// Home card uses, on a high pixel-density real device, where a long-haul great circle's
        /// peak arc is exactly where a coarser sample count used to leave visible facets. Cheap
        /// either way — a couple thousand trig calls, not a rendering bottleneck. Deliberately
        /// left in raw (non-unwrapped) coordinate
        /// form — `MKMapPoint`'s conversion from `CLLocationCoordinate2D` expects longitude in
        /// its normal ±180° range, so unwrapping happens exactly once, afterward, in map-point
        /// space (`unwrappedMapPoints`) rather than here too; doing it at both stages fed already-
        /// out-of-range longitudes back into `MKMapPoint`, corrupting the projection for any route
        /// whose great-circle path swings past ±180° (common for near-polar routes) and was the
        /// actual cause of the map fitting to a tiny, wrong sub-region instead of the real route.
        private static func routeSamples(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
            let sampleCount = 1500
            var coordinates: [CLLocationCoordinate2D] = [a]
            for i in 1..<sampleCount {
                coordinates.append(intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)))
            }
            coordinates.append(b)
            return coordinates
        }

        /// `MKMapPoint.x` runs monotonically west-to-east across a single flat Mercator strip —
        /// it has no concept of "the short way around." Unwrapping longitude incrementally across
        /// the sequence, here in map-point space (the one place it happens — see `routeSamples`),
        /// keeps every sample's x consistent even where the curve crosses the antimeridian, so
        /// both the drawn line and the camera-fitting bounds span the route's real short way
        /// across rather than jumping back around through the opposite hemisphere.
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
}

/// A plain `MKMapView` that also reports its own `layoutSubviews` — used to catch the moment
/// SwiftUI actually gives this view a real, non-zero frame (see the `onLayout` wiring in
/// `MapKitRouteView.makeUIView`), since `makeUIView` itself runs before that layout pass happens.
private final class SizeAwareMapView: MKMapView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Carries per-annotation metadata (`MKPointAnnotation` alone has no room for it) so the
/// delegate's `viewFor annotation:` can tell markers apart and render the right SwiftUI content.
private final class RouteAnnotation: MKPointAnnotation {
    enum Kind { case origin, destination, position }

    let kind: Kind
    let reuseIdentifier: String
    var positionHeading: Double?
    var travelers: [Person] = []
    var currentUserID: Person.ID?
    /// `.origin`/`.destination` only — whether the position marker currently sits on this exact
    /// endpoint, which needs the label pushed further down to stay clear of it.
    var hasOverlappingMarker = false

    init(kind: Kind, reuseIdentifier: String) {
        self.kind = kind
        self.reuseIdentifier = reuseIdentifier
        super.init()
    }
}

/// A route polyline carrying its own render styling — used for both the white casing and the
/// blue line on top of it (see `Coordinator.updateOverlays`), since a plain `MKPolyline` has no
/// room to say which is which.
///
/// Deliberately a plain `MKPolyline` subclass built from manually-sampled points, not
/// `MKGeodesicPolyline` — that was tried, and while safe to *use* unsubclassed, its own adaptive
/// point insertion was noticeably sparser than this manual sampling, leaving a visible facet at
/// the peak of a long-haul arc. Subclassing `MKGeodesicPolyline` directly is also unsafe on its
/// own terms: giving it extra stored properties and constructing via `init(coordinates:count:)`
/// reliably crashed with `EXC_BAD_ACCESS` inside `objc_release`, consistent with its geodesic
/// point-insertion internals assuming the base class's exact memory layout. Plain `MKPolyline`
/// has neither problem.
private final class ColoredPolyline: MKPolyline {
    var strokeColor: UIColor = .gray
    var lineWidth: CGFloat = 4
}

/// Hosts SwiftUI marker content inside an `MKAnnotationView` — a standard SwiftUI-in-UIKit bridge
/// (a `UIHostingController` whose view is added as a subview), not anything MapKit-specific.
private final class SwiftUIAnnotationView: MKAnnotationView {
    private var hostingController: UIHostingController<AnyView>?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setContent<Content: View>(_ content: Content, size: CGSize, centerOffset: CGPoint = .zero) {
        bounds = CGRect(origin: .zero, size: size)
        self.centerOffset = centerOffset
        if let hostingController {
            hostingController.rootView = AnyView(content)
        } else {
            let host = UIHostingController(rootView: AnyView(content))
            host.view.backgroundColor = .clear
            host.view.frame = bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(host.view)
            hostingController = host
        }
    }
}
