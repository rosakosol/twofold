//
//  TripsGlobeView.swift
//  Twofold
//
//  The Trips list's hero — a real interactive MapKit globe (same "very high camera distance +
//  hybrid realistic-elevation style renders the earth as a rotatable 3D sphere" technique
//  `RelationshipGlobeView` uses on Home), generalized from that view's single partner-to-partner
//  route to one geodesic route per upcoming trip. Endpoints are deduped by place (two trips
//  sharing a home-city origin get one pin, not two stacked ones) — just a plain dot marker per
//  place, not per-traveler avatars, so the globe reads as routes-and-places first.
//

import CoreLocation
import MapKit
import SwiftUI

struct TripsGlobeView: View {
    let trips: [Trip]
    /// Falls back to this for the initial camera framing when there are no trips yet (e.g. the
    /// current user's own home city) — nil renders a generic wide-world view instead.
    var fallbackCenter: CLLocationCoordinate2D?
    /// How much of the bottom of this view's own layout frame the docked browse panel actually
    /// covers — used to center the globe within the *visible* remaining area above it, rather
    /// than the full frame including the space the panel already occupies (which pushed the
    /// globe visibly low, looking like it was sinking into the panel). Defaults to 0 for the
    /// preview below, where there's no panel to account for.
    var reservedBottomHeight: CGFloat = 0

    @State private var cameraPosition: MapCameraPosition

    init(trips: [Trip], fallbackCenter: CLLocationCoordinate2D? = nil, reservedBottomHeight: CGFloat = 0) {
        self.trips = trips
        self.fallbackCenter = fallbackCenter
        self.reservedBottomHeight = reservedBottomHeight

        let center: CLLocationCoordinate2D
        if let first = trips.first {
            // The destination itself, not the spherical midpoint between origin and destination —
            // for a trip anywhere near a third of the way around the globe (e.g. LA → Melbourne),
            // that midpoint lands in open ocean nowhere near either city, so the initial view
            // framed on it looked like it was centered on nothing recognizable at all.
            center = first.destination.coordinate
        } else {
            center = fallbackCenter ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
        }
        // Much further out than `RelationshipGlobeView`'s equivalent (22_000_000) — that view
        // renders into a small Home card where framing tightly around the two endpoints reads
        // fine, but this is a full-screen globe, where the same distance only ever shows a
        // close horizon curve. MapKit clamps `MapCamera.distance` internally somewhere around
        // this value regardless of how much higher it's set (confirmed empirically — 300_000_000
        // rendered pixel-for-pixel identical to this), so getting the globe to look smaller/more
        // zoomed out than this has to happen visually instead — see `.scaleEffect` below.
        _cameraPosition = State(initialValue: .camera(MapCamera(centerCoordinate: center, distance: 60_000_000, heading: 0, pitch: 0)))
    }

    /// One pin per unique place across every trip, not one pair per trip — a shared home-city
    /// origin (the common case: every trip starts from wherever you live) would otherwise stack
    /// duplicate overlapping dots at the exact same coordinate.
    private var endpoints: [Place] {
        var byPlaceID: [UUID: Place] = [:]
        for trip in trips {
            byPlaceID[trip.origin.id] = trip.origin
            byPlaceID[trip.destination.id] = trip.destination
        }
        return Array(byPlaceID.values)
    }

    /// How much smaller the globe should look on screen than MapKit renders it natively — the
    /// *final* displayed diameter is always `proxy.size.width * visualScale`, independent of
    /// however big a frame it takes to render MapKit's sphere without clipping (below).
    private let visualScale: CGFloat = 0.72
    /// How much *larger* a (square) frame to actually give MapKit than the container, before
    /// scaling the whole thing back down to `visualScale` — MapKit renders the sphere at a size
    /// tied to camera distance alone, not to the frame it's given, so a frame narrower than the
    /// sphere's rendered diameter clips it flat at the frame's own edges *before* any
    /// `.scaleEffect` below ever sees the result; shrinking an already-clipped image afterward
    /// keeps the flat edges, just smaller. This container is a tall, narrow portrait rect, so
    /// sizing the oversized frame off its *width* alone (`proxy.size.width * oversizeFactor`)
    /// was still narrower than the sphere's native diameter and kept clipping flat on the sides
    /// even at a 2.4x factor. Squaring the frame off the *larger* of width/height instead
    /// guarantees it's generously bigger than the sphere regardless of how narrow the visible
    /// container is.
    private let oversizeFactor: CGFloat = 2.4

    var body: some View {
        GeometryReader { proxy in
            // Clamped to a sane minimum — during a `NavigationStack` push/pop transition this
            // view's `GeometryReader` can momentarily report a proposed size of (0, 0) before
            // settling, which drove `mapDimension` to exactly 0. Handing MapKit's Metal-backed
            // layer a zero-size (or otherwise degenerate) frame fails Metal's own texture
            // validation and hard-crashes the whole app (`MTLTextureDescriptorInternal
            // validateWithDevice:` → `abort()`), rather than just rendering nothing for a frame.
            let safeWidth = max(proxy.size.width, 1)
            let safeHeight = max(proxy.size.height, 1)
            let mapDimension = max(safeWidth, safeHeight) * oversizeFactor
            // Scales the oversized render down to a fixed final diameter tied to the container's
            // own width (not to `mapDimension`, which varies with `oversizeFactor` and exists
            // purely to dodge MapKit's clip) — so the on-screen globe size stays exactly what
            // `visualScale` alone would produce, whatever oversizing was needed to get there.
            let displayScale = (safeWidth * visualScale) / mapDimension
            // Centered within the space actually visible above the docked panel, not the full
            // layout frame (which includes the space the panel covers) — otherwise the globe
            // reads as sitting too low, sinking toward/behind the panel instead of centered in
            // the open black area above it.
            let visibleHeight = max(0, proxy.size.height - reservedBottomHeight)

            // `.pan` only (excluding `.zoom`) — a pinch-to-zoom would change the camera's live
            // `distance`, and the sphere's natively rendered diameter scales with that distance.
            // `mapDimension` above is only ever sized to fit the sphere at this view's *fixed*
            // initial distance, so any live zoom-in renders a larger sphere than that frame was
            // built for, and MapKit clips it flat at the frame edges again — on every side this
            // time, not just left/right — reproducing the exact clipping bug `oversizeFactor` was
            // meant to fix. `.pan` alone still lets a drag spin the globe (dragging across a
            // sphere camera rotates it), which is the one interaction this hero visual is meant
            // to support.
            Map(position: $cameraPosition, interactionModes: .pan) {
                ForEach(trips) { trip in
                    // Reunion trips read as the "main event" (solid, heavier line); everything
                    // else is a lighter, more translucent route — same visual hierarchy
                    // `passportCard`'s hero framing already gives reunion travel over any other
                    // trip.
                    MapPolyline(coordinates: [trip.origin.coordinate, trip.destination.coordinate], contourStyle: .geodesic)
                        .stroke(
                            Theme.skyBlue.opacity(trip.isReunionTrip ? 0.9 : 0.55),
                            style: StrokeStyle(lineWidth: trip.isReunionTrip ? 3 : 2, lineCap: .round, dash: [1, 9])
                        )
                }

                ForEach(endpoints) { place in
                    Annotation(place.displayCity, coordinate: place.coordinate) {
                        Circle().fill(Theme.skyBlue).frame(width: 10, height: 10)
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))
            .mapControlVisibility(.hidden)
            .frame(width: mapDimension, height: mapDimension)
            .scaleEffect(displayScale)
            .position(x: proxy.size.width / 2, y: visibleHeight / 2)
        }
    }
}

#Preview {
    TripsGlobeView(trips: MockData.trips)
        .containerRelativeFrame(.vertical) { height, _ in height * 0.6 }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
}
