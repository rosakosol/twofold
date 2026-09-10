//
//  FlightConfirmationView.swift
//  Twofold
//
//  Confirmation step — link to a trip, decide on notifications, then actually starts tracking
//  via `add-flight`. Presented as a sheet from AddFlightResultsStepView when the live app's
//  AddFlightFlowView completion is `.confirmAndTrack`.
//

import SwiftUI
import PostHog

struct FlightConfirmationView: View {
    let candidate: AeroFlightCandidate
    var onDone: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkedTripID: Trip.ID?
    /// Defaults to the person adding the flight. "Not sure yet" used to be here and was the
    /// default, which meant the common case — adding your own flight — needed a tap to correct,
    /// and any flight left alone was saved with nobody on it. A flight has someone on it; that is
    /// what makes it worth tracking.
    @State private var travelerChoice: TravelerChoice = .me
    @State private var shareWithPartner = true
    @State private var notifyMe = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Nil until the lookup returns, and left nil if it fails — an allowance we could not read is
    /// not an allowance of zero, and the server refuses on its own anyway. Every use below treats
    /// nil as "don't get in the way".
    @State private var allowance: BackendService.FlightAllowance?

    /// Set when this search was opened from a specific trip's "Link a flight" screen's "Create
    /// new" option — preselects "Link to a trip" below to that trip, rather than leaving it at
    /// "None" and relying on the caller to remember to pick it again.
    init(candidate: AeroFlightCandidate, initialTripID: Trip.ID? = nil, onDone: @escaping () -> Void) {
        self.candidate = candidate
        self.onDone = onDone
        _linkedTripID = State(initialValue: initialTripID)
    }

    private enum TravelerChoice: Hashable {
        case me, partner, both
    }

    private var isOutOfAllowance: Bool { allowance?.remaining == 0 }

    /// What the allowance line says. Written as flights left rather than flights used, because
    /// the question being asked at this exact moment is whether this one will go through.
    private var allowanceMessage: String? {
        guard let allowance else { return nil }
        switch allowance.remaining {
        case 0:
            return "You've tracked all \(allowance.limit) flights your plan includes this month. Your allowance resets on the 1st."
        case 1:
            return "1 flight left this month, shared with your partner."
        default:
            return "\(allowance.remaining) of \(allowance.limit) flights left this month, shared with your partner."
        }
    }

    private var travelerIDs: [UUID] {
        switch travelerChoice {
        case .me: [appModel.currentUser.id]
        case .partner: [appModel.partner.id]
        case .both: [appModel.currentUser.id, appModel.partner.id]
        }
    }

    /// Every trip is linkable, not just ones with no flight yet — a trip's real itinerary can be
    /// more than one tracked flight (e.g. a connecting journey), so this flight might be a second
    /// or third leg rather than the first.
    private var linkableTrips: [Trip] {
        appModel.trips
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
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                            Text(candidate.destination?.city ?? candidate.destination?.iata ?? "—")
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .accessibilityElement(children: .combine)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Who's travelling?").font(.caption).foregroundStyle(Theme.subtleInk)
                        Picker("Who's travelling?", selection: $travelerChoice) {
                            Text(appModel.currentUser.name).tag(TravelerChoice.me)
                            // Disabled rather than just warned-about — `appModel.partner` is a
                            // placeholder person pre-pairing, with no real profile row behind its
                            // id, so letting this actually get submitted as a flight's traveler
                            // would attribute it to someone who doesn't exist yet. `FlightConfirmationView`
                            // only ever runs in the live app (never during onboarding — see
                            // `AddFlightFlowView.Completion.confirmAndTrack`'s doc comment), so
                            // there's no "partner isn't connected yet" exemption to make here.
                            // Same reasoning applies to "Both", since it includes the partner.
                            Text(appModel.partner.name).tag(TravelerChoice.partner)
                                .disabled(!appModel.partnerConnected)
                            Text("Both of us").tag(TravelerChoice.both)
                                .disabled(!appModel.partnerConnected)
                        }
                        .pickerStyle(.segmented)
                    }

                    if !linkableTrips.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Link to a trip").font(.caption).foregroundStyle(Theme.subtleInk)
                            Picker("Link to a trip", selection: $linkedTripID) {
                                Text("None").tag(Trip.ID?.none)
                                ForEach(linkableTrips) { trip in
                                    Text("\(trip.origin.displayCity) → \(trip.destination.displayCity)").tag(Trip.ID?.some(trip.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .themedCardBackground(cornerRadius: Theme.Radius.card)
                        }
                    }

                    SectionCard {
                        Toggle("Share with \(appModel.partner.name)", isOn: $shareWithPartner)
                            .font(.subheadline.weight(.medium))
                        Text(shareWithPartner
                            ? "\(appModel.partner.name) will see the same live status and get their own notifications for this flight."
                            : "Only visible to you — \(appModel.partner.name) won't see this flight or get notified about it.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)

                        Divider()

                        Toggle("Track this flight", isOn: $notifyMe)
                            .font(.subheadline.weight(.medium))
                        Text("Get live status updates and alerts as this flight progresses — including once tracking kicks in, if it's not trackable yet.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    if !candidate.canTrack {
                        // Schedule-only candidate — AeroAPI hasn't assigned it a trackable flight
                        // instance yet (normally resolves a few days before departure). Still
                        // addable: the server persists it as a pending flight and starts full live
                        // tracking automatically once a real instance is assigned — no separate
                        // "activate tracking" step for the caller to remember to come back for.
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: "clock.badge.questionmark").foregroundStyle(Theme.subtleInk)
                            Text("Not trackable live yet — it's on the airline's schedule, and we'll start tracking automatically once it is (usually a few days before departure).")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .themedCardBackground(cornerRadius: Theme.Radius.card)
                    }

                    // Shown before the button rather than only after a refusal: the allowance is
                    // the couple's, so someone can be out of flights because their partner spent
                    // them, and finding that out by tapping Add Flight is the wrong order.
                    if let allowanceMessage {
                        Text(allowanceMessage)
                            .font(.caption)
                            .foregroundStyle(isOutOfAllowance ? Theme.heartRed : Theme.subtleInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                    }

                    Button(action: confirm) {
                        HStack {
                            if isSaving { ProgressView().tint(.white) }
                            Text(isSaving ? "Saving…" : "Add Flight")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .disabled(isSaving || isOutOfAllowance)
                    .opacity(isOutOfAllowance ? 0.5 : 1)
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
        .task {
            allowance = try? await BackendService.flightAllowance(coupleID: appModel.couple.id)
        }
        .postHogScreenView("Flights: Flight Confirmation")
    }

    private func confirm() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await AeroFlightService.addFlight(candidate: candidate, tripID: linkedTripID, travelerIDs: travelerIDs, shared: shareWithPartner, notifyMe: notifyMe)
                await appModel.refreshFlights()
                onDone()
            } catch {
                errorMessage = (error as? AeroFlightError)?.errorDescription ?? "Couldn't save that flight. Try again."
                isSaving = false
            }
        }
    }
}
