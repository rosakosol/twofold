//
//  FlightMapSection.swift
//  Twofold
//
//  Flight Details' map, and the button that locks its camera onto the plane.
//

import SwiftUI

/// Just the map and the camera-lock button. It used to carry a readout of the live telemetry
/// too — groundspeed in knots, altitude in feet, and wind before those — and none of it
/// answered the question this screen exists for. Someone waiting on a flight wants to know
/// where it is and when it lands, which the map and the cards below say plainly; a number in a
/// unit they don't think in was clutter sitting on top of the one thing worth looking at.
///
/// The readings are still on `Flight` and still polled, so nothing here stops them being shown
/// again somewhere they earn their place.
struct FlightMapSection: View {
    let flight: Flight

    /// Incremented to explicitly re-trigger the map's camera fit/follow — see
    /// `FlightMapView.recenterNonce`/`Coordinator.apply`.
    ///
    /// Written by the map as well as read: touching the map releases the lock, and this follows it
    /// so the button stops looking active the moment it stops being.
    @State private var mapRecenterNonce = 0
    /// Whether the map's camera is locked onto the plane. See `recenterButton`.
    @State private var isCameraLocked = false

    var body: some View {
        FlightMapView(flight: flight, recenterNonce: mapRecenterNonce, followsAircraft: $isCameraLocked)
            // 260pt at phone width. At the ~900pt of iPhone Duo's inner display a fixed 260 was a
            // letterbox strip with the route lost in the middle of it.
            .proportionalHeight(260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if flight.origin.coordinate != nil, flight.destination.coordinate != nil {
                    recenterButton
                }
            }
    }

    /// Puts the camera back, and — while a flight is airborne — locks it onto the plane so it
    /// keeps up as the plane moves.
    ///
    /// That lock is why this now shows its own state. It was invisible: the button looked like a
    /// one-shot "recentre", but tapping it also left the camera following, and a following camera
    /// quietly overrides panning every second. Nothing on screen said which mode the map was in, so
    /// the map felt like it sometimes ignored a drag. Lit blue means locked and the map will keep
    /// up with the plane; dark means the camera is yours. Touching the map releases it, which is
    /// what someone panning already means.
    ///
    /// For a flight that is not airborne there is nothing to lock onto, so the button stays a
    /// one-shot refit of the whole route and never lights up — the map corrects the flag back if
    /// the lock could not engage.
    private var recenterButton: some View {
        Button {
            if isCameraLocked {
                isCameraLocked = false
            } else {
                // Both: the flag engages the lock for an airborne flight, and the nonce refits the
                // route for one that is not. Whichever applies, the camera goes back where it
                // belongs.
                isCameraLocked = true
                mapRecenterNonce += 1
            }
        } label: {
            Image(systemName: "airplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.onFill)
                .padding(10)
                .background(isCameraLocked ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(.black.opacity(0.55)), in: Circle())
                .overlay {
                    if isCameraLocked {
                        Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5)
                    }
                }
        }
        .padding(Theme.Spacing.sm)
        .animation(.snappy(duration: 0.2), value: isCameraLocked)
        .accessibilityLabel(isCameraLocked ? "Camera locked to the plane" : "Recentre the map")
        .accessibilityHint(isCameraLocked ? "Unlocks the camera" : "Follows the plane while it's in the air")
    }
}
