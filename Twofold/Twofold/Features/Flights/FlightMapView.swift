//
//  FlightMapView.swift
//  Twofold
//
//  Shared map used by both the Home active-flight card (compact) and the full flight detail
//  screen. Built on MapLibre (`MLNMapView`, UIKit) rather than Apple MapKit — MapKit's SwiftUI
//  `Map` couldn't give real vector-style control, a gradient route line, or arbitrary SwiftUI
//  content hosted at an annotation, so this bridges MapLibre in directly via
//  `UIViewRepresentable` instead of reaching for a third-party SwiftUI wrapper package, trading a
//  little more code here for full control over camera fitting, line-layer styling, and markers.
//  Tiles/style come from OpenFreeMap (free, no API key — see `MapLibreStyle`).
//

import CoreLocation
import MapLibre
import SwiftUI
import UIKit

struct FlightMapView: View {
    @Environment(AppModel.self) private var appModel
    let flight: Flight
    var interactive: Bool = true
    /// Minimum padding (screen points) reserved around the fitted route on every edge, passed
    /// straight through to `MLNMapView.setVisibleCoordinates(_:count:edgePadding:animated:)` —
    /// MapLibre computes the exact camera to keep the whole route inside (frame - this padding),
    /// so unlike the old MapKit implementation there's no manual bounding-box math to get wrong.
    var edgePadding: CGFloat = 40

    /// Resolved directly from the flight (set explicitly when adding it) rather than a linked
    /// trip — flights don't require one, so this is the only reliable source now.
    private var traveler: Person? {
        flight.travelerID.flatMap { appModel.couple.partner($0) }
    }

    var body: some View {
        if let origin = flight.origin.coordinate, let destination = flight.destination.coordinate {
            MapLibreRouteView(
                origin: origin,
                destination: destination,
                originCode: flight.origin.displayCode,
                destinationCode: flight.destination.displayCode,
                position: flight.positionCoordinate,
                positionHeading: flight.positionHeading,
                traveler: traveler,
                interactive: interactive,
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

/// The MapLibre map itself. A thin `UIViewRepresentable` shell — all the real work (building the
/// route source/layers, placing annotations, fitting the camera) happens in `Coordinator`, which
/// persists across SwiftUI body re-evaluations exactly like the underlying `MLNMapView` does.
private struct MapLibreRouteView: UIViewRepresentable {
    let origin: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
    let originCode: String
    let destinationCode: String
    let position: CLLocationCoordinate2D?
    let positionHeading: Double?
    let traveler: Person?
    let interactive: Bool
    let edgePadding: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let mapView = MLNMapView(frame: .zero, styleURL: MapLibreStyle.openFreeMapLiberty)
        mapView.delegate = context.coordinator
        mapView.logoView.isHidden = true
        mapView.compassView.isHidden = true
        mapView.isZoomEnabled = interactive
        mapView.isScrollEnabled = interactive
        mapView.isRotateEnabled = interactive
        mapView.isPitchEnabled = false
        context.coordinator.mapView = mapView
        context.coordinator.apply(route(), edgePadding: edgePadding)
        return mapView
    }

    func updateUIView(_ mapView: MLNMapView, context: Context) {
        context.coordinator.apply(route(), edgePadding: edgePadding)
    }

    private func route() -> Coordinator.Route {
        Coordinator.Route(
            origin: origin,
            destination: destination,
            originCode: originCode,
            destinationCode: destinationCode,
            position: position,
            positionHeading: positionHeading,
            traveler: traveler
        )
    }

    /// Owns the `MLNMapView` delegate callbacks, the route source/line layers, and the three
    /// annotations (origin, destination, live/traveler position).
    final class Coordinator: NSObject, MLNMapViewDelegate {
        struct Route: Equatable {
            var origin: CLLocationCoordinate2D
            var destination: CLLocationCoordinate2D
            var originCode: String
            var destinationCode: String
            var position: CLLocationCoordinate2D?
            var positionHeading: Double?
            var traveler: Person?

            static func == (lhs: Route, rhs: Route) -> Bool {
                lhs.origin.latitude == rhs.origin.latitude && lhs.origin.longitude == rhs.origin.longitude
                    && lhs.destination.latitude == rhs.destination.latitude && lhs.destination.longitude == rhs.destination.longitude
                    && lhs.originCode == rhs.originCode && lhs.destinationCode == rhs.destinationCode
                    && lhs.position?.latitude == rhs.position?.latitude && lhs.position?.longitude == rhs.position?.longitude
                    && lhs.positionHeading == rhs.positionHeading && lhs.traveler?.id == rhs.traveler?.id
            }
        }

        private static let sourceIdentifier = "flight-route"
        private static let casingLayerIdentifier = "flight-route-casing"
        private static let gradientLayerIdentifier = "flight-route-gradient"
        private static let originIdentifier = "flight-origin"
        private static let destinationIdentifier = "flight-destination"
        private static let positionIdentifier = "flight-position"

        weak var mapView: MLNMapView?

        private var styleIsLoaded = false
        private var hasBuiltRoute = false
        private var hasFittedCamera = false
        private var pendingRoute: Route?
        private var pendingEdgePadding: CGFloat = 40
        private var lastAppliedRoute: Route?

        private var originAnnotation: RouteAnnotation?
        private var destinationAnnotation: RouteAnnotation?
        private var positionAnnotation: RouteAnnotation?
        private var originHasOverlappingMarker = false
        private var destinationHasOverlappingMarker = false

        func apply(_ route: Route, edgePadding: CGFloat) {
            pendingRoute = route
            pendingEdgePadding = edgePadding
            guard styleIsLoaded, let mapView, let style = mapView.style else { return }
            guard lastAppliedRoute != route else { return }
            render(route, edgePadding: edgePadding, style: style, mapView: mapView)
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleIsLoaded = true
            if let pendingRoute {
                render(pendingRoute, edgePadding: pendingEdgePadding, style: style, mapView: mapView)
            }
        }

        func mapView(_ mapView: MLNMapView, viewFor annotation: any MLNAnnotation) -> MLNAnnotationView? {
            guard let annotation = annotation as? RouteAnnotation else { return nil }
            let identifier = annotation.reuseIdentifier
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SwiftUIAnnotationView
                ?? SwiftUIAnnotationView(reuseIdentifier: identifier)
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
                    centerOffset: CGVector(dx: 0, dy: size.height / 2 - 5)
                )
            case .position:
                if let traveler = annotation.traveler {
                    view.setContent(Self.travelerMarker(traveler), size: CGSize(width: 44, height: 44))
                } else {
                    view.setContent(Self.planeMarker(heading: annotation.positionHeading), size: CGSize(width: 30, height: 30))
                }
            }
            return view
        }

        // MARK: - Building the route

        private func render(_ route: Route, edgePadding: CGFloat, style: MLNStyle, mapView: MLNMapView) {
            let samples = Self.routeSamples(from: route.origin, to: route.destination)

            if !hasBuiltRoute {
                buildRoute(samples: samples, style: style)
                hasBuiltRoute = true
            } else if let source = style.source(withIdentifier: Self.sourceIdentifier) as? MLNShapeSource {
                source.shape = MLNPolyline(coordinates: samples, count: UInt(samples.count))
            }

            updateEndpointAnnotations(route, mapView: mapView)
            updatePositionAnnotation(route, mapView: mapView)

            if !hasFittedCamera {
                // Endpoint labels hang below their coordinate, not around it symmetrically (see
                // `endpointMarker`/`endpointMarkerSize`) — whichever endpoint lands at the bottom
                // of the fitted route needs that much extra clearance below it, or its label gets
                // clipped by the card's edge instead of just sitting there unread. Sized for the
                // worst case (a traveler avatar parked on that endpoint) since this fit only runs
                // once, before it's necessarily known whether that'll happen later.
                let labelClearance = Self.endpointMarkerSize(hasOverlappingMarker: true).height - 5
                let insets = UIEdgeInsets(top: edgePadding, left: edgePadding, bottom: edgePadding + labelClearance, right: edgePadding)
                mapView.setVisibleCoordinates(samples, count: UInt(samples.count), edgePadding: insets, animated: false)
                hasFittedCamera = true
            }

            lastAppliedRoute = route
        }

        private func buildRoute(samples: [CLLocationCoordinate2D], style: MLNStyle) {
            let polyline = MLNPolyline(coordinates: samples, count: UInt(samples.count))
            let source = MLNShapeSource(
                identifier: Self.sourceIdentifier,
                shape: polyline,
                options: [MLNShapeSourceOption.lineDistanceMetrics: true]
            )
            style.addSource(source)

            // A light halo underneath a solid, higher-contrast line — even a saturated gradient
            // can wash out against ocean/land on the basemap, so the white outline keeps it
            // legible everywhere regardless of what's underneath.
            let casing = MLNLineStyleLayer(identifier: Self.casingLayerIdentifier, source: source)
            casing.lineJoin = NSExpression(forConstantValue: "round")
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineColor = NSExpression(forConstantValue: UIColor.white)
            casing.lineOpacity = NSExpression(forConstantValue: 0.9)
            casing.lineWidth = NSExpression(forConstantValue: 6)
            style.addLayer(casing)

            let gradient = MLNLineStyleLayer(identifier: Self.gradientLayerIdentifier, source: source)
            gradient.lineJoin = NSExpression(forConstantValue: "round")
            gradient.lineCap = NSExpression(forConstantValue: "round")
            gradient.lineWidth = NSExpression(forConstantValue: 4)
            gradient.lineGradient = NSExpression(
                forMLNInterpolating: NSExpression.lineProgressVariable,
                curveType: .linear,
                parameters: nil,
                stops: NSExpression(forConstantValue: [
                    0: UIColor(Theme.skyBlue),
                    1: UIColor(Theme.leafGreen),
                ])
            )
            style.addLayer(gradient)
        }

        /// Whether the live/traveler-at-origin position marker (see `updatePositionAnnotation`)
        /// sits exactly on a given endpoint right now — the one case where that endpoint's label
        /// needs extra clearance underneath it.
        private func markerCoordinate(for route: Route) -> CLLocationCoordinate2D? {
            route.position ?? (route.traveler != nil ? route.origin : nil)
        }

        private func updateEndpointAnnotations(_ route: Route, mapView: MLNMapView) {
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

        /// Removed and re-added (rather than mutated in place) on every position update — the
        /// live position is the one thing about a flight that changes on its own timer, and
        /// explicit remove/add avoids relying on undocumented in-place-repositioning behavior.
        ///
        /// Before departure there's no live position from the provider yet, but if a traveler is
        /// set, their avatar still rides the route — parked at the origin — rather than only
        /// appearing once the flight is airborne. Without a traveler there's nothing meaningful
        /// to show pre-departure (the plane-icon fallback is for an in-progress flight only), so
        /// no marker is added.
        private func updatePositionAnnotation(_ route: Route, mapView: MLNMapView) {
            if let existing = positionAnnotation {
                mapView.removeAnnotation(existing)
                positionAnnotation = nil
            }
            guard let coordinate = markerCoordinate(for: route) else { return }
            let annotation = RouteAnnotation(kind: .position, reuseIdentifier: Self.positionIdentifier)
            annotation.coordinate = coordinate
            annotation.positionHeading = route.positionHeading
            annotation.traveler = route.traveler
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

        private static func planeMarker(heading: Double?) -> some View {
            ZStack {
                Circle().fill(Theme.skyBlue)
                Image(systemName: "airplane")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    // SF Symbols' "airplane" glyph points due east (right) at rotation 0 —
                    // verified by rendering it at several rotations and comparing, since the
                    // commonly-assumed "points ~45° NE at rotation 0" turned out to be wrong.
                    .rotationEffect(.degrees(90 - (heading ?? 0)))
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

        /// Samples 16 points along the great-circle curve (plus both endpoints) and unwraps
        /// longitude incrementally across the sequence so a route crossing the antimeridian
        /// doesn't jump back around through the opposite hemisphere. `MLNMapView` requires the
        /// caller to do this unwrapping itself — it doesn't happen automatically (confirmed
        /// against the SDK's own header docs, which describe passing longitudes outside ±180°
        /// to bring both sides of the antimeridian into view).
        private static func routeSamples(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
            let sampleCount = 16
            var coordinates: [CLLocationCoordinate2D] = [a]
            for i in 1..<sampleCount {
                coordinates.append(intermediateGreatCirclePoint(a, b, fraction: Double(i) / Double(sampleCount)))
            }
            coordinates.append(b)

            for i in 1..<coordinates.count {
                while coordinates[i].longitude - coordinates[i - 1].longitude > 180 {
                    coordinates[i].longitude -= 360
                }
                while coordinates[i].longitude - coordinates[i - 1].longitude < -180 {
                    coordinates[i].longitude += 360
                }
            }
            return coordinates
        }
    }
}

/// Carries per-annotation metadata (`MLNPointAnnotation` alone has no room for it) so the
/// delegate's `viewForAnnotation` can tell markers apart and render the right SwiftUI content.
private final class RouteAnnotation: MLNPointAnnotation {
    enum Kind { case origin, destination, position }

    let kind: Kind
    let reuseIdentifier: String
    var positionHeading: Double?
    var traveler: Person?
    /// `.origin`/`.destination` only — whether the position marker currently sits on this exact
    /// endpoint, which needs the label pushed further down to stay clear of it.
    var hasOverlappingMarker = false

    init(kind: Kind, reuseIdentifier: String) {
        self.kind = kind
        self.reuseIdentifier = reuseIdentifier
        super.init()
    }

    required init?(coder: NSCoder) {
        self.kind = .origin
        self.reuseIdentifier = ""
        super.init(coder: coder)
    }
}

/// Hosts SwiftUI marker content inside a MapLibre annotation view — `MLNAnnotationView` is plain
/// UIKit, so this is the standard SwiftUI-in-UIKit bridge (a `UIHostingController` whose view is
/// added as a subview), not anything MapLibre-specific.
private final class SwiftUIAnnotationView: MLNAnnotationView {
    private var hostingController: UIHostingController<AnyView>?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setContent<Content: View>(_ content: Content, size: CGSize, centerOffset: CGVector = .zero) {
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
