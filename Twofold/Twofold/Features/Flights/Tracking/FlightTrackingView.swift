//
//  FlightTrackingView.swift
//  Twofold
//
//  The full flight detail / live-tracking screen — takes a `Flight` directly (not a `Trip`)
//  since a flight can exist and be tracked without ever being linked to one. Real
//  AeroAPI-sourced data (times, position, weather, events) renders "Not available" rather
//  than a fabricated value wherever the provider hasn't supplied it yet.
//
//  The cards themselves live beside this file, one per file; this screen owns the data they show —
//  the flight, its events and documents, the delay stats and the notification preferences — and
//  keeps it live while it is open.
//

import PostHog
import Supabase
import SwiftUI

struct FlightTrackingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var flight: Flight
    @State private var events: [FlightStatusEvent] = []
    @State private var documents: [FlightDocument] = []
    /// 60-day on-time performance for this flight's designator — nil while loading or on any
    /// failure (network, or AeroAPI erroring for an account-tier reason); `FlightDelayAnalysisCard`
    /// simply doesn't render in that case, same as every other optional AeroAPI-sourced section
    /// on this screen.
    @State private var delayStats: DelayStats?
    /// Which Premium-gated card was tapped while locked — drives `FlightPremiumGateView`'s sheet.
    /// An `Identifiable` enum rather than a plain `Bool` since three different cards share one
    /// gate view, each with its own icon/copy.
    @State private var premiumGateFeature: PremiumFlightFeature?
    @State private var isRefreshing = false
    @State private var eventsChannel: RealtimeChannelV2?
    @State private var flightChannel: RealtimeChannelV2?
    /// Stored so `.onDisappear` can cancel these directly rather than relying solely on
    /// `unsubscribe(_:)` ending the underlying `AsyncStream` — these are bare `Task { }`s (not
    /// `.task {}`), so nothing cancels them automatically on disappear otherwise.
    @State private var eventsTask: Task<Void, Never>?
    @State private var flightUpdateTask: Task<Void, Never>?

    // Notification preferences — individually-bound so the toggles feel instant; saved as one
    // upsert on change.
    @State private var notificationToggles = FlightNotificationToggles()
    @State private var preferencesLoaded = false
    @State private var showingShare = false

    init(flight: Flight) {
        _flight = State(initialValue: flight)
    }

    private var linkedTrip: Trip? {
        guard let tripID = flight.tripID else { return nil }
        return appModel.trips.first { $0.id == tripID }
    }

    /// The one rule every flight surface uses — the flight's own, then its trip's, then whoever
    /// added it (`Flight.travellerIDs(linkedTrip:)`, FLT-14).
    private var travelerIDs: [Person.ID] {
        flight.travellerIDs(linkedTrip: linkedTrip)
    }

    private var travelers: [Person] {
        travelerIDs.compactMap { appModel.couple.partner($0) }
    }

    private var navigationTitleText: String {
        switch travelers.count {
        case 0: "Flight \(flight.displayNumber)"
        case 1: "\(travelers[0].name)'s journey"
        default: "Your journey together"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Fixed/sticky — deliberately outside the ScrollView below, so it never scrolls with
            // the rest of the screen. Route, airline, status, and countdown are the things worth
            // always having on screen regardless of how far down you've scrolled. In dark mode
            // this is the screen's one hero card (one gradient per screen) — everything below it
            // (journeyCard, departureCard, ...) stays a flat `SectionCard`.
            Group {
                if colorScheme == .dark {
                    FlightTrackingHeader(flight: flight).heroCard(padding: Theme.Spacing.md)
                } else {
                    FlightTrackingHeader(flight: flight)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, Theme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    FlightNotTrackedCard(flight: flight)
                    FlightMapSection(flight: flight)
                    FlightDocumentsCard(flight: flight, documents: $documents)
                    FlightJourneyCard(flight: flight)
                    FlightDepartureCard(flight: flight)
                    FlightArrivalCard(flight: flight)
                    FlightUpdatesCard(flight: flight, events: events)
                    FlightDelayAnalysisCard(flight: flight, delayStats: delayStats, onLocked: { premiumGateFeature = $0 })
                    FlightGoodToKnowCard(flight: flight, onLocked: { premiumGateFeature = $0 })
                    FlightInfoCard(flight: flight, onLocked: { premiumGateFeature = $0 })
                    // A cancelled/diverted flight can't be tracked any further — AeroAPI has
                    // nothing left to poll toward gate/departure/landing/baggage milestones that
                    // will ever actually fire, so offering toggles for them read as broken
                    // promises rather than real settings.
                    if flight.status != .cancelled, flight.status != .diverted {
                        FlightNotificationPrefsCard(toggles: $notificationToggles, onChange: savePreferencesIfLoaded)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await refreshFromProvider() }
        }
        .background(ScreenBackground())
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShare = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Edit travellers") {
                        Button {
                            toggleTraveler(appModel.currentUser.id)
                        } label: {
                            Label(appModel.currentUser.name, systemImage: flight.travelerIDs.contains(appModel.currentUser.id) ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            toggleTraveler(appModel.partner.id)
                        } label: {
                            Label(appModel.partner.name, systemImage: flight.travelerIDs.contains(appModel.partner.id) ? "checkmark.circle.fill" : "circle")
                        }
                        if !flight.travelerIDs.isEmpty {
                            Button(role: .destructive) {
                                setTravelers([])
                            } label: {
                                Label("Clear", systemImage: "xmark.circle")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
            }
        }
        .task { await loadEverything() }
        .onDisappear {
            if let eventsChannel { Task { await BackendService.unsubscribe(eventsChannel) } }
            if let flightChannel { Task { await BackendService.unsubscribe(flightChannel) } }
            // Belt-and-suspenders alongside the unsubscribes above: cancelling directly doesn't
            // depend on `unsubscribe(_:)` actually closing the stream to end these loops.
            eventsTask?.cancel()
            flightUpdateTask?.cancel()
        }
        // Pushed onto this screen's own NavigationStack rather than presented as a second sheet
        // on top of Flight Details — same reasoning as TripDetailsView's edit flow.
        .sheet(item: $premiumGateFeature) { feature in
            FlightPremiumGateView(icon: feature.icon, title: feature.title, description: feature.description)
        }
        .sheet(isPresented: $showingShare) {
            FlightShareView(flight: flight)
        }
        .postHogScreenView("Flights: Flight Details")
    }

    /// Travelers used to be write-once (set only at add-flight time, in
    /// `FlightConfirmationView`) with no way to change them afterward — same gap `linkFlight`/
    /// `unlinkFlight` closed for trip linking. Mutates the local `flight` copy immediately for
    /// snappy UI, same pattern `refreshFromProvider()` already uses elsewhere on this screen.
    /// Reachable via the toolbar's "..." menu (Edit Travellers) — no standalone card on the
    /// screen itself anymore; the nav title already names the current traveler(s).
    private func setTravelers(_ travelerIDs: [UUID]) {
        flight.travelerIDs = travelerIDs
        Task { await appModel.setFlightTravelers(flight, travelerIDs: travelerIDs) }
    }

    /// Adds or removes a single person from the traveler list — lets both partners be marked as
    /// travelling together, rather than picking one exclusively.
    private func toggleTraveler(_ id: UUID) {
        var ids = flight.travelerIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        setTravelers(ids)
    }

    private func savePreferencesIfLoaded() {
        guard preferencesLoaded, let userID = BackendService.currentUserID else { return }
        Task {
            try? await BackendService.upsertNotificationPreferences(FlightNotificationPreferences(
                flightID: flight.id, profileID: userID,
                gateTerminalChanges: notificationToggles.gateTerminalChanges,
                delayOrCancellation: notificationToggles.delayOrCancellation,
                departure: notificationToggles.departureNotif, landing: notificationToggles.landingNotif,
                arrivalAtGate: notificationToggles.arrivalAtGateNotif,
                baggageClaimUpdate: notificationToggles.baggageClaimNotif
            ))
        }
    }

    // MARK: - Loading / refreshing

    private func loadEverything() async {
        if let fetched = try? await BackendService.fetchFlightStatusEvents(flightID: flight.id) {
            events = fetched
        }
        if let fetched = try? await BackendService.fetchFlightDocuments(flightID: flight.id) {
            documents = fetched
        }
        // Premium-gated (see FlightDelayAnalysisCard) — skip the AeroAPI history call entirely for
        // Plus/free accounts rather than paying for a fetch nobody can see the result of.
        if !appModel.isPremiumLocked, let stats = try? await AeroFlightService.fetchDelayStats(flightID: flight.id) {
            delayStats = stats
        }
        if let prefs = try? await BackendService.fetchNotificationPreferences(flightID: flight.id) {
            notificationToggles.gateTerminalChanges = prefs.gateTerminalChanges
            notificationToggles.delayOrCancellation = prefs.delayOrCancellation
            notificationToggles.departureNotif = prefs.departure
            notificationToggles.landingNotif = prefs.landing
            notificationToggles.arrivalAtGateNotif = prefs.arrivalAtGate
            notificationToggles.baggageClaimNotif = prefs.baggageClaimUpdate
        }
        preferencesLoaded = true

        let (channel, stream) = BackendService.subscribeToFlightStatusEvents(flightID: flight.id)
        eventsChannel = channel
        eventsTask = Task {
            for await event in stream where !events.contains(where: { $0.id == event.id }) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    events.insert(event, at: 0)
                }
            }
        }

        // Picks up the server-side 5-minute polling cron's writes to this row while the screen
        // is open, instead of only ever refreshing on initial load or an explicit pull-to-refresh.
        let (flightUpdateChannel, flightUpdateStream) = BackendService.subscribeToFlightRefresh(flightID: flight.id)
        flightChannel = flightUpdateChannel
        flightUpdateTask = Task {
            for await _ in flightUpdateStream {
                if let fresh = try? await BackendService.fetchFlight(id: flight.id) {
                    withAnimation(.easeInOut(duration: 0.3)) { flight = fresh.keepingTimeZones(from: flight) }
                }
            }
        }

        await refreshFromProvider()
    }

    private func refreshFromProvider() async {
        // `faFlightID == nil` (a pending, not-yet-trackable flight) is deliberately NOT excluded
        // here — refresh-flight's server-side refreshOneFlight now attempts to resolve a real
        // faFlightID for exactly this case, so a pull-to-refresh (or this screen's initial
        // .task-triggered call) should give it a chance to do that immediately rather than only
        // waiting for the next cron tick.
        guard !isRefreshing, flight.trackingEnabled else { return }
        isRefreshing = true
        try? await AeroFlightService.refreshFlight(id: flight.id)
        // The raw row has no zone for a schedule-only flight; keep the ones already resolved, or
        // every time on this screen falls back to home time a second after opening (FLT-6).
        if let fresh = try? await BackendService.fetchFlight(id: flight.id) {
            flight = fresh.keepingTimeZones(from: flight)
        }
        isRefreshing = false
    }
}

#Preview {
    NavigationStack {
        FlightTrackingView(flight: MockData.reunionTrip.mostRelevantFlight ?? MockData.activeFlight)
    }
    .environment(AppModel())
}
