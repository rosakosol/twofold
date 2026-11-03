//
//  FlightNotTrackedCard.swift
//  Twofold
//
//  Flight Details' offer to start tracking a flight saved without it.
//

import SwiftUI

/// A flight saved while the couple's monthly allowance was spent.
///
/// Above the map on purpose. Everything below it — position, status, times — is frozen at
/// whatever the add captured, and without this the screen looks like tracking that has simply
/// stopped working rather than tracking that was never turned on.
struct FlightNotTrackedCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight

    @State private var isEnablingTracking = false
    @State private var enableTrackingError: String?

    /// See `FlightTrackingHeader.isPastTracking`.
    private var isPastTracking: Bool {
        flight.isOver()
    }

    @ViewBuilder
    var body: some View {
        if !flight.trackingEnabled, !isPastTracking {
            SectionCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(Theme.textSecondary)
                        Text("Not being tracked")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("This flight is saved, but it isn't being followed — no status updates, "
                        + "alerts or Live Activity. Turning tracking on uses one of this month's "
                        + "live-tracked flights.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let enableTrackingError {
                        Text(enableTrackingError).font(.caption).foregroundStyle(Theme.error)
                    }

                    Button(action: enableTracking) {
                        HStack {
                            if isEnablingTracking { ProgressView().controlSize(.small) }
                            Text(isEnablingTracking ? "Turning on…" : "Turn on live tracking")
                        }
                    }
                    .buttonStyle(.twofoldPrimary)
                    .disabled(isEnablingTracking)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Spends a slot, or explains why it could not.
    ///
    /// The refusal is the server's to make — `enable_flight_tracking` owns both the allowance and
    /// the subscription check — so a `false` here is a real answer rather than an error, and says
    /// the one thing the person can act on. Which sentence that is depends on which refusal it was:
    /// the allowance one told a lapsed couple to wait for the 1st, which never helps them.
    private func enableTracking() {
        isEnablingTracking = true
        enableTrackingError = nil
        Task {
            defer { isEnablingTracking = false }
            do {
                let result = try await BackendService.enableFlightTracking(flightID: flight.id)
                if result.enabled {
                    await appModel.travel.refreshFlights()
                } else {
                    enableTrackingError = BackendService.FlightTrackingRefusal.message(for: result.reason)
                }
            } catch {
                enableTrackingError = "Couldn't turn tracking on. Try again."
            }
        }
    }
}
