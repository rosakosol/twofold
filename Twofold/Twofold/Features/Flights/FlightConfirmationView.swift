//
//  FlightConfirmationView.swift
//  Twofold
//
//  Confirmation step — link to a trip, decide on notifications, then actually starts tracking
//  via `add-flight`. Presented as a sheet from AddFlightResultsStepView when the live app's
//  AddFlightFlowView completion is `.confirmAndTrack`.
//

import SwiftUI

struct FlightConfirmationView: View {
    let candidate: AeroFlightCandidate
    var onDone: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkedTripID: Trip.ID?
    @State private var travelerID: Person.ID?
    @State private var notifyMe = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var flightlessTrips: [Trip] {
        appModel.trips.filter { $0.flight == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: Theme.Spacing.sm) {
                            AirlineLogoView(url: candidate.logoURL, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.displayFlightNumber).font(.title2.weight(.bold))
                                if let operatorName = candidate.operatorName {
                                    Text(operatorName).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                        }
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(candidate.origin?.city ?? candidate.origin?.iata ?? "—")
                            Image(systemName: "arrow.right")
                            Text(candidate.destination?.city ?? candidate.destination?.iata ?? "—")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Who's travelling?").font(.caption).foregroundStyle(Theme.subtleInk)
                        Picker("Who's travelling?", selection: $travelerID) {
                            Text("Not sure yet").tag(Person.ID?.none)
                            Text(appModel.currentUser.name).tag(Person.ID?.some(appModel.currentUser.id))
                            Text(appModel.partner.name).tag(Person.ID?.some(appModel.partner.id))
                        }
                        .pickerStyle(.segmented)
                    }

                    if !flightlessTrips.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Link to a trip").font(.caption).foregroundStyle(Theme.subtleInk)
                            Picker("Link to a trip", selection: $linkedTripID) {
                                Text("None").tag(Trip.ID?.none)
                                ForEach(flightlessTrips) { trip in
                                    Text("\(trip.origin.city) → \(trip.destination.city)").tag(Trip.ID?.some(trip.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                    }

                    SectionCard {
                        Toggle("Notify me about this flight", isOn: $notifyMe)
                            .font(.subheadline.weight(.medium))
                        Text("Shared with \(appModel.partner.name) automatically — they'll see the same live status.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                    }

                    Button(action: confirm) {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : "Track this flight")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .disabled(isSaving)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func confirm() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await AeroFlightService.addFlight(faFlightId: candidate.faFlightId, tripID: linkedTripID, travelerID: travelerID, notifyMe: notifyMe)
                await appModel.refreshFlights()
                onDone()
            } catch {
                errorMessage = (error as? AeroFlightError)?.errorDescription ?? "Couldn't save that flight. Try again."
                isSaving = false
            }
        }
    }
}
