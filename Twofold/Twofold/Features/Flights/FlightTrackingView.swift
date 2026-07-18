//
//  FlightTrackingView.swift
//  Twofold
//
//  The full flight detail / live-tracking screen — takes a `Flight` directly (not a `Trip`)
//  since a flight can exist and be tracked without ever being linked to one. Real
//  AeroAPI-sourced data (times, position, weather, events) renders "Not available" rather
//  than a fabricated value wherever the provider hasn't supplied it yet.
//

import PhotosUI
import Supabase
import SwiftUI
import UniformTypeIdentifiers

struct FlightTrackingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var flight: Flight
    @State private var events: [FlightStatusEvent] = []
    @State private var showAllEvents = false
    @State private var documents: [FlightDocument] = []
    /// 60-day on-time performance for this flight's designator — nil while loading or on any
    /// failure (network, or AeroAPI erroring for an account-tier reason); `delayAnalysisCard`
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
    /// Incremented to explicitly re-trigger the map's camera fit/follow — see
    /// `FlightMapView.recenterNonce`/`Coordinator.apply`.
    @State private var mapRecenterNonce = 0

    // Notification preferences — individually-bound so the toggles feel instant; saved as one
    // upsert on change.
    @State private var gateTerminalChanges = true
    @State private var delayOrCancellation = true
    @State private var departureNotif = true
    @State private var landingNotif = true
    @State private var arrivalAtGateNotif = true
    @State private var baggageClaimNotif = true
    @State private var preferencesLoaded = false

    // Document upload — tapping a card shows a `Menu` (anchored right at the card, unlike a
    // `confirmationDialog`'s forced bottom sheet) asking which source to pull from, then routes
    // to exactly one of the three pickers below.
    @State private var photosPickerDocType: FlightDocumentType?
    @State private var cameraDocType: FlightDocumentType?
    @State private var fileImporterDocType: FlightDocumentType?
    @State private var documentPickerItem: PhotosPickerItem?
    @State private var isUploadingDocument = false
    @State private var showingTripNotes = false
    @State private var tripNotesDraft = ""

    // Legacy self-reported "log an update" — only meaningful when this flight is linked to a
    // trip with a known traveler (the feature predates independent flights).
    @State private var selfReportedUpdates: [FlightUpdate] = []
    @State private var noteDraft = ""
    @State private var isSendingUpdate = false
    @State private var selfReportChannel: RealtimeChannelV2?

    init(flight: Flight) {
        _flight = State(initialValue: flight)
    }

    private var linkedTrip: Trip? {
        guard let tripID = flight.tripID else { return nil }
        return appModel.trips.first { $0.id == tripID }
    }

    /// The flight's own `travelerIDs` (set explicitly when adding it) takes priority since
    /// flights don't require a linked trip; the trip's traveler is a fallback for older/
    /// trip-linked flights that predate that field.
    private var travelerIDs: [Person.ID] {
        flight.travelerIDs.isEmpty ? linkedTrip.map { [$0.travelerID] } ?? [] : flight.travelerIDs
    }

    private var isTraveler: Bool {
        travelerIDs.contains(appModel.currentUser.id)
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
            // always having on screen regardless of how far down you've scrolled.
            header
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    mapSection
                    documentsSection
                    journeyCard
                    departureCard
                    arrivalCard
                    updatesCard
                    delayAnalysisCard
                    goodToKnowCard
                    flightInfoCard
                    if linkedTrip != nil, isTraveler {
                        legacyLogUpdateCard
                    }
                    if !selfReportedUpdates.isEmpty {
                        legacyUpdatesCard
                    }
                    notificationPreferencesCard
                }
                .padding(Theme.Spacing.md)
            }
            .refreshable { await refreshFromProvider() }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Menu {
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
                    } label: {
                        Label("Edit Travellers", systemImage: "person.crop.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await loadEverything() }
        .onDisappear {
            if let eventsChannel { Task { await BackendService.unsubscribe(eventsChannel) } }
            if let flightChannel { Task { await BackendService.unsubscribe(flightChannel) } }
            if let selfReportChannel { Task { await BackendService.unsubscribe(selfReportChannel) } }
        }
        .sheet(isPresented: $showingTripNotes) {
            tripNotesSheet
        }
        .sheet(item: $premiumGateFeature) { feature in
            FlightPremiumGateView(icon: feature.icon, title: feature.title, description: feature.description)
        }
    }

    // MARK: - Premium gating

    private enum PremiumFlightFeature: String, Identifiable {
        case delayAnalysis, goodToKnow, flightInfo
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .delayAnalysis: "chart.bar.fill"
            case .goodToKnow: "sparkles"
            case .flightInfo: "airplane.circle.fill"
            }
        }

        var title: String {
            switch self {
            case .delayAnalysis: "Delay Analysis"
            case .goodToKnow: "Good to Know"
            case .flightInfo: "Flight Information"
            }
        }

        var description: String {
            switch self {
            case .delayAnalysis: "60-day on-time performance for this flight number is part of Twofold Premium. Upgrade to see punctuality stats for every flight you track."
            case .goodToKnow: "Weather and time-zone context for your route is part of Twofold Premium. Upgrade to see it for every flight you track."
            case .flightInfo: "Aircraft type and registration details are part of Twofold Premium. Upgrade to see them for every flight you track."
            }
        }
    }

    /// Compact teaser shown in place of a Premium-only card's real content — same "you can see it
    /// exists, tap to unlock" shape as the games tab's locked deck cards, adapted to a full-width
    /// card here instead of a small badge.
    private func premiumLockedCard(_ feature: PremiumFlightFeature) -> some View {
        Button {
            premiumGateFeature = feature
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.sm) {
                    ZStack {
                        Circle().fill(Theme.subtleInk.opacity(0.08))
                        Image(systemName: "lock.fill").font(.subheadline).foregroundStyle(Theme.subtleInk)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text("Unlock with Premium").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "crown.fill").font(.caption).foregroundStyle(Theme.skyBlue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if flight.airlineName != nil || !flight.flightNumberIATA.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    AirlineLogoView(url: flight.displayLogoURL, size: 28)
                    Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }
            }

            Text("\(flight.origin.displayName) → \(flight.destination.displayName)")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Spacing.sm) {
                PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
                if flight.isDelayed, flight.status != .cancelled {
                    Image(systemName: flight.status.icon).font(.caption2).foregroundStyle(Theme.heartRed)
                }
                Text(flight.countdownSummary)
                    .font(.title2.weight(.bold))
            }

            // Every time elsewhere on this screen (journey rows, departure/arrival cards) is
            // deliberately shown in *that airport's* local time, which is easy to misread as
            // "my time" and mistake for a bug — this one line anchors the same key moment in
            // the user's own home-city time instead, e.g. "4:30pm (Melbourne time)".
            if let userLocalTimeLabel {
                Text(userLocalTimeLabel)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }

            if !flight.trackingEnabled {
                // Explains why pulling to refresh here won't visibly do anything, instead of a
                // spinner that cycles and stops with nothing to show for it.
                Text("No longer being tracked — this flight's history is kept for reference.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
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

    private var shareText: String {
        "\(flight.displayNumber) · \(flight.origin.displayCode) → \(flight.destination.displayCode) — \(flight.countdownSummary)"
    }

    /// Mirrors `countdownSummary`'s own choice of "the next relevant moment" (departure
    /// pre-departure, arrival once en route/landed) so the header's two lines always describe
    /// the same instant — one counting down to it, the other anchoring it in the user's time.
    private var referenceEventDate: Date? {
        switch flight.status {
        case .cancelled, .diverted:
            return nil
        case .arrived, .landed, .landingSoon, .inAir, .departed, .boarding:
            return flight.bestArrival
        case .scheduled, .delayed:
            return flight.bestDeparture
        }
    }

    private var userLocalTimeLabel: String? {
        guard let date = referenceEventDate else { return nil }
        let timeZone = appModel.currentUser.homeCity?.timeZone ?? .current
        // Date included alongside the time, not just hour:minute — a countdown like "1d 9h"
        // crossing midnight is easy to misjudge against "today" without an explicit day/month
        // to anchor it, which read as the countdown itself being wrong when it wasn't.
        let dateTimeString = date.formatted(Date.FormatStyle(timeZone: timeZone).hour().minute().day().month(.abbreviated))
        let offset = TimeMath.utcOffsetLabel(for: timeZone, at: date)
        guard let cityName = appModel.currentUser.homeCity?.city else { return "\(dateTimeString) your time (\(offset))" }
        return "\(dateTimeString) (\(cityName), \(offset))"
    }

    // MARK: - Map

    private var mapSection: some View {
        FlightMapView(flight: flight, recenterNonce: mapRecenterNonce)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                // `hasLivePosition` only checks lat/lon — AeroAPI's own position fallback (used
                // when the free ADS-B mirrors haven't picked up this aircraft yet, e.g. an
                // oceanic leg outside terrestrial receiver coverage) can return a fix with no
                // altitude/groundspeed at all, which rendered as an empty capsule with nothing
                // inside it. Only show the overlay once there's actually something to put in it.
                if flight.positionGroundspeed != nil || flight.positionAltitude != nil {
                    liveStatsOverlay
                }
            }
            .overlay(alignment: .topTrailing) {
                if flight.origin.coordinate != nil, flight.destination.coordinate != nil {
                    recenterButton
                }
            }
    }

    /// Speed/altitude readout directly on the map itself, bottom-right — alongside (not instead
    /// of) the `StatTile` row below, which also carries heading and stays as the more detailed,
    /// labeled version. Dark translucent pill regardless of theme, since it needs to stay legible
    /// sitting on top of whatever's under it on the map (ocean blue, green terrain, ...), not
    /// whatever the app's light/dark mode happens to be.
    private var liveStatsOverlay: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let speed = flight.positionGroundspeed {
                Label("\(Int(speed))kn", systemImage: "speedometer")
            }
            if let altitude = flight.positionAltitude {
                Label("\(Int(altitude))ft", systemImage: "arrow.up.to.line")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(Theme.Spacing.sm)
    }

    /// Pinch/zoom/pan already work on this map — this button just puts the camera back to its
    /// sensible default (re-centers on the live position while en route, or refits the whole
    /// route otherwise) after a user has panned away from it. Same dark-translucent treatment as
    /// `liveStatsOverlay` so both read as one visual language on top of the map.
    private var recenterButton: some View {
        Button {
            mapRecenterNonce += 1
        } label: {
            Image(systemName: "airplane")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.55), in: Circle())
        }
        .padding(Theme.Spacing.sm)
    }

    // MARK: - Journey summary

    /// Unlike the departure/arrival cards below (which deliberately stay in each airport's own
    /// local time — the useful frame while actually there), this quick-glance summary card shows
    /// both legs in the user's own home-city time, so a glance at the phone answers "when do I
    /// need to be ready" without a timezone conversion.
    private var homeTimeZone: TimeZone { appModel.currentUser.homeCity?.timeZone ?? .current }

    private var journeyCard: some View {
        SectionCard {
            if flight.airlineName != nil || !flight.flightNumberIATA.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    AirlineLogoView(url: flight.displayLogoURL, size: 24)
                    Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                }
            }

            journeyRow(
                code: flight.origin.displayCode, city: flight.origin.displayName,
                time: flight.bestDeparture, timeZone: homeTimeZone,
                terminal: flight.terminalOrigin, gate: flight.gateOrigin,
                statusLine: departureStatusLine
            )

            HStack {
                Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(width: 2, height: 28).padding(.leading, 15)
                Spacer()
            }

            journeyRow(
                code: flight.destination.displayCode, city: flight.destination.displayName,
                time: flight.bestArrival, timeZone: homeTimeZone,
                terminal: flight.terminalDestination, gate: flight.gateDestination,
                statusLine: arrivalStatusLine
            )
        }
    }

    private var departureStatusLine: String {
        if flight.actualOut != nil { return "Departed \(Self.relativeShort(flight.actualOut!)) ago" }
        if let scheduled = flight.bestDeparture { return scheduled > .now ? "Departs \(Self.relativeShort(scheduled))" : "Departing shortly" }
        return "Not available"
    }

    private var arrivalStatusLine: String {
        if flight.actualIn != nil { return "Arrived \(Self.relativeShort(flight.actualIn!)) ago" }
        if let arrival = flight.bestArrival { return arrival > .now ? "Arrives in \(Self.relativeShort(arrival))" : "Arriving shortly" }
        return "Not available"
    }

    private func journeyRow(code: String, city: String, time: Date?, timeZone: TimeZone?, terminal: String?, gate: String?, statusLine: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                Image(systemName: "airplane").font(.caption).foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(code) · \(city)").font(.headline)
                if let time {
                    Text(time, format: Date.FormatStyle(timeZone: timeZone ?? .current).day().month(.abbreviated).hour().minute())
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Time not available").font(.subheadline).foregroundStyle(Theme.subtleInk)
                }
                Text(Self.terminalGateLine(terminal: terminal, gate: gate))
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                Text(statusLine)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.skyBlue)
            }
            Spacer(minLength: 0)
        }
    }

    private static func terminalGateLine(terminal: String?, gate: String?) -> String {
        switch (terminal, gate) {
        case (.some(let t), .some(let g)): return "Terminal \(t) · Gate \(g)"
        case (.some(let t), nil): return "Terminal \(t) · Gate not available"
        case (nil, .some(let g)): return "Gate \(g)"
        case (nil, nil): return "Terminal & gate not available"
        }
    }

    // MARK: - Departure / Arrival cards

    /// Port/city used to live buried in an "Airport" detail row below; pulled up here, inline
    /// with the card's own title and a departing/arriving plane glyph, so it reads at a glance
    /// instead of requiring a scan down the row list.
    private func portCardHeader(icon: String, title: String, code: String, city: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text("\(code) · \(city)").font(.caption).foregroundStyle(Theme.subtleInk)
            }
            Spacer(minLength: 0)
        }
    }

    private var departureCard: some View {
        SectionCard {
            portCardHeader(icon: "airplane.departure", title: "Departure", code: flight.origin.displayCode, city: flight.origin.displayName)
            Text("All times shown in local time").font(.caption2).foregroundStyle(Theme.subtleInk)
            detailRow(label: "Scheduled", value: Self.timeOrNA(flight.scheduledOut, timeZone: flight.origin.timeZone))
            detailRow(label: flight.actualOut != nil ? "Actual" : "Estimated", value: Self.timeOrNA(flight.actualOut ?? flight.estimatedOut, timeZone: flight.origin.timeZone))
            if let delta = Self.delayDelta(scheduled: flight.scheduledOut, actualOrEstimated: flight.actualOut ?? flight.estimatedOut) {
                delayDeltaCaption(delta)
            }
            detailRow(label: "Terminal", value: flight.terminalOrigin ?? "Not available")
            detailRow(label: "Gate", value: flight.gateOrigin ?? "Not available")
        }
    }

    private var arrivalCard: some View {
        SectionCard {
            portCardHeader(icon: "airplane.arrival", title: "Arrival", code: flight.destination.displayCode, city: flight.destination.displayName)
            Text("All times shown in local time").font(.caption2).foregroundStyle(Theme.subtleInk)
            detailRow(label: "Scheduled", value: Self.timeOrNA(flight.scheduledIn, timeZone: flight.destination.timeZone))
            detailRow(label: flight.actualIn != nil ? "Actual" : "Estimated", value: Self.timeOrNA(flight.actualIn ?? flight.estimatedIn, timeZone: flight.destination.timeZone))
            if let delta = Self.delayDelta(scheduled: flight.scheduledIn, actualOrEstimated: flight.actualIn ?? flight.estimatedIn) {
                delayDeltaCaption(delta)
            }
            detailRow(label: "Terminal", value: flight.terminalDestination ?? "Not available")
            detailRow(label: "Gate", value: flight.gateDestination ?? "Not available")
            detailRow(label: "Baggage claim", value: flight.baggageClaim ?? "Not available")
        }
    }

    private func detailRow(label: String, value: String, tint: Color = Theme.ink) -> some View {
        let isUnavailable = value == "Not available"
        return HStack {
            Text(label).font(.caption).foregroundStyle(Theme.subtleInk)
            Spacer()
            Text(value)
                .font(.subheadline.weight(isUnavailable ? .regular : .medium))
                .foregroundStyle(isUnavailable ? Theme.subtleInk.opacity(0.6) : tint)
        }
    }

    private struct DelayDelta {
        let text: String
        let color: Color
    }

    /// "On time" covers the same 0–14 minute window as `delayAnalysisCard`'s "On time" bucket
    /// (the standard on-time-performance definition — within 15 minutes of schedule), so this
    /// caption and the historical stats above never disagree about what counts as on time.
    private static func delayDelta(scheduled: Date?, actualOrEstimated: Date?) -> DelayDelta? {
        guard let scheduled, let actualOrEstimated else { return nil }
        let minutes = Int((actualOrEstimated.timeIntervalSince(scheduled) / 60).rounded())
        if minutes <= -1 { return DelayDelta(text: "\(abs(minutes)) min early", color: Theme.leafGreen) }
        if minutes < 15 { return DelayDelta(text: "On time", color: Theme.leafGreen) }
        return DelayDelta(text: "+\(minutes) min", color: Theme.heartRed)
    }

    private func delayDeltaCaption(_ delta: DelayDelta) -> some View {
        HStack {
            Spacer()
            Text(delta.text).font(.caption2.weight(.semibold)).foregroundStyle(delta.color)
        }
    }

    private static func timeOrNA(_ date: Date?, timeZone: TimeZone?) -> String {
        guard let date else { return "Not available" }
        return date.formatted(Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute().day().month(.abbreviated))
    }

    // MARK: - Good to know

    /// Weather (moved here from the departure/arrival cards) and the time difference between
    /// the two airports, in one place — never rendered empty.
    private var hasAnyWeather: Bool {
        flight.weatherOrigin?.isEmpty == false || flight.weatherDestination?.isEmpty == false
    }

    @ViewBuilder
    private var goodToKnowCard: some View {
        if hasAnyWeather || (flight.origin.timeZone != nil && flight.destination.timeZone != nil) {
            if appModel.isPremiumLocked {
                premiumLockedCard(.goodToKnow)
            } else {
            SectionCard {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.skyBlue)
                    Text("Good to know").font(.subheadline.weight(.semibold))
                }

                if hasAnyWeather {
                    HStack(spacing: Theme.Spacing.sm) {
                        weatherPanel(code: flight.origin.displayCode, weather: flight.weatherOrigin)
                        weatherPanel(code: flight.destination.displayCode, weather: flight.weatherDestination)
                    }
                }

                timeDifferenceSection
            }
            }
        }
    }

    private func weatherPanel(code: String, weather: FlightWeather?) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(code).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Image(systemName: Self.weatherIcon(for: weather?.conditions))
                .font(.title2)
                .foregroundStyle(.white)
            Text(weather?.temperatureC.map { "\(Int($0))°C" } ?? "—")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(weather?.windSummary ?? " ")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            LinearGradient(colors: [Theme.skyBlue, Theme.skyBlue.opacity(0.65)], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private static func weatherIcon(for conditions: String?) -> String {
        guard let c = conditions?.lowercased() else { return "cloud.fill" }
        if c.contains("storm") || c.contains("thunder") { return "cloud.bolt.rain.fill" }
        if c.contains("snow") { return "cloud.snow.fill" }
        if c.contains("rain") || c.contains("shower") { return "cloud.rain.fill" }
        if c.contains("fog") || c.contains("mist") || c.contains("haze") { return "cloud.fog.fill" }
        if c.contains("cloud") || c.contains("overcast") { return "cloud.fill" }
        if c.contains("clear") || c.contains("sun") { return "sun.max.fill" }
        return "cloud.fill"
    }

    /// Reuses the same day/night gradient idiom as the Home screen's `TimeZoneCard` (see
    /// `TimeMath.hourFraction`/`daylightFactor` + `Theme.DayNight`) rather than inventing a
    /// third visual language for "what time is it there."
    @ViewBuilder
    private var timeDifferenceSection: some View {
        if let originTZ = flight.origin.timeZone, let destTZ = flight.destination.timeZone {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let hoursApart = Int((Double(destTZ.secondsFromGMT(for: context.date) - originTZ.secondsFromGMT(for: context.date)) / 3600).rounded())
                HStack(spacing: Theme.Spacing.sm) {
                    timeZoneChip(code: flight.origin.displayCode, timeZone: originTZ, date: context.date)
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.left.and.right").font(.caption2)
                        Text(hoursApart == 0 ? "Same time" : "\(hoursApart > 0 ? "+" : "")\(hoursApart)h")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Theme.subtleInk)
                    .frame(width: 56)
                    timeZoneChip(code: flight.destination.displayCode, timeZone: destTZ, date: context.date)
                }
            }
        }
    }

    private func timeZoneChip(code: String, timeZone: TimeZone, date: Date) -> some View {
        let hour = TimeMath.hourFraction(in: timeZone, at: date)
        let isDaytime = hour >= 6 && hour < 18
        return VStack(spacing: 4) {
            Image(systemName: isDaytime ? "sun.max.fill" : "moon.stars.fill")
                .font(.caption)
                .foregroundStyle(isDaytime ? Theme.skyBlue : Theme.subtleInk)
            Text(code).font(.caption2.weight(.semibold)).foregroundStyle(Theme.subtleInk)
            Text(TimeMath.timeString(in: timeZone, at: date)).font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.subtleInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Updates timeline

    /// Excludes the baseline "scheduled" event (that's just when the flight was added to
    /// tracking, not a real schedule) and other low-signal milestones — see `isKeyUpdate`.
    private var keyEvents: [FlightStatusEvent] {
        events.filter { $0.type.isKeyUpdate }
    }

    private var updatesCard: some View {
        SectionCard {
            HStack {
                Text("Flight updates").font(.subheadline.weight(.semibold))
                Spacer()
                if keyEvents.count > 4 {
                    Button(showAllEvents ? "Show less" : "Show all") { showAllEvents.toggle() }
                        .font(.caption.weight(.medium))
                }
            }

            if keyEvents.isEmpty {
                Text("No updates yet - we'll show gate changes, delays, and milestones here as they happen.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                ForEach(showAllEvents ? keyEvents : Array(keyEvents.prefix(4))) { event in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(event.type.isUrgent ? Theme.heartRed.opacity(0.15) : Theme.skyBlue.opacity(0.15))
                            Image(systemName: event.type.icon).font(.caption).foregroundStyle(event.type.isUrgent ? Theme.heartRed : Theme.skyBlue)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.label(timeZone: flight.destination.timeZone)).font(.subheadline.weight(.medium))
                            Text(event.occurredAt, format: Date.FormatStyle(timeZone: flight.origin.timeZone ?? .current).hour().minute())
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    // MARK: - Flight information (technical)

    @ViewBuilder
    private var flightInfoCard: some View {
        if flight.aircraftType != nil || flight.registration != nil {
            if appModel.isPremiumLocked {
                premiumLockedCard(.flightInfo)
            } else {
                SectionCard {
                    Text("Flight information").font(.subheadline.weight(.semibold))
                    detailRow(label: "Aircraft", value: flight.aircraftType ?? "Not available")
                    detailRow(label: "Registration", value: flight.registration ?? "Not available")
                }
            }
        }
    }

    // MARK: - Delay analysis

    /// This flight designator's on-time performance over the last 60 days (not this specific
    /// tracked instance's own delay) — server-computed/cached, see `AeroFlightService.
    /// fetchDelayStats`. Renders nothing while loading or on any failure (network, or the AeroAPI
    /// account not being on a tier with historical data access), same as every other
    /// optional-data section on this screen — never a spinner or an error message here.
    @ViewBuilder
    private var delayAnalysisCard: some View {
        if appModel.isPremiumLocked {
            premiumLockedCard(.delayAnalysis)
        } else if let delayStats {
            SectionCard {
                Text("\(flight.displayNumber) · Past 60 days")
                    .font(.subheadline.weight(.semibold))

                HStack {
                    delayHeadlineStat(
                        value: "\(Int((delayStats.earlyPercent + delayStats.onTimePercent).rounded()))%",
                        label: "Punctual"
                    )
                    Spacer()
                    delayHeadlineStat(value: "\(Int(delayStats.averageLateMinutes.rounded()))m", label: "Average Delay")
                    Spacer()
                    delayHeadlineStat(value: "\(delayStats.observedCount)", label: "Observed Flights")
                }

                VStack(spacing: Theme.Spacing.xs) {
                    delayBucketRow(label: "Early", percent: delayStats.earlyPercent, color: Theme.leafGreen)
                    delayBucketRow(label: "On time", percent: delayStats.onTimePercent, color: Theme.leafGreen)
                    delayBucketRow(label: "15m late", percent: delayStats.late15Percent, color: .orange)
                    delayBucketRow(label: "30m late", percent: delayStats.late30Percent, color: .orange)
                    delayBucketRow(label: "45m+ late", percent: delayStats.late45Percent, color: Theme.heartRed)
                    delayBucketRow(label: "Cancelled", percent: delayStats.cancelledPercent, color: Theme.heartRed)
                    delayBucketRow(label: "Diverted", percent: delayStats.divertedPercent, color: Theme.heartRed)
                }
            }
        }
    }

    private func delayHeadlineStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func delayBucketRow(label: String, percent: Double, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .frame(width: 72, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.subtleInk.opacity(0.08))
                    Capsule().fill(color).frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
                }
            }
            .frame(height: 8)

            Text("\(Int(percent.rounded()))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                documentActionCard(type: .boardingPass, title: "Boarding pass")
                documentActionCard(type: .itinerary, title: "Itinerary")
                documentActionCard(type: .other, title: "Documents")
            }

            if linkedTrip != nil {
                Button {
                    tripNotesDraft = linkedTrip?.notes ?? ""
                    showingTripNotes = true
                } label: {
                    HStack {
                        documentCardIcon(.system("checklist"))
                        Text("Trip checklist").font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if !documents.isEmpty {
                ForEach(documents) { document in
                    HStack {
                        flightDocumentIcon(document.docType.icon, size: 16)
                            .foregroundStyle(Theme.skyBlue)
                        Text(document.originalFilename ?? document.docType.label).font(.caption)
                        Spacer()
                        if let url = document.url {
                            Link("View", destination: url).font(.caption.weight(.medium))
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                }
            }
        }
        .photosPicker(isPresented: Binding(get: { photosPickerDocType != nil }, set: { if !$0 { photosPickerDocType = nil } }), selection: $documentPickerItem, matching: .images)
        .onChange(of: documentPickerItem) { _, newItem in
            guard let newItem, let docType = photosPickerDocType else { return }
            photosPickerDocType = nil
            Task { await uploadPickedPhoto(newItem, type: docType) }
        }
        .fullScreenCover(isPresented: Binding(get: { cameraDocType != nil }, set: { if !$0 { cameraDocType = nil } })) {
            if let docType = cameraDocType {
                CameraPicker(
                    onCapture: { image in
                        cameraDocType = nil
                        Task { await uploadImageDocument(image, type: docType) }
                    },
                    onCancel: { cameraDocType = nil }
                )
                .ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: Binding(get: { fileImporterDocType != nil }, set: { if !$0 { fileImporterDocType = nil } }),
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false
        ) { result in
            guard let docType = fileImporterDocType else { return }
            fileImporterDocType = nil
            if case .success(let urls) = result, let url = urls.first {
                Task { await uploadFileDocument(at: url, type: docType) }
            }
        }
    }

    /// Boarding passes/travel documents can come from anywhere the traveler happens to have
    /// them saved — a photo they took at check-in, a screenshot, or a PDF/pass file saved from
    /// Mail or Wallet's own "Save to Files" share action (there's no public API to browse a
    /// user's existing Wallet passes directly from a third-party app, so Files is the closest,
    /// honest equivalent).
    private func documentActionCard(type: FlightDocumentType, title: String) -> some View {
        // `Menu` (not `confirmationDialog`) deliberately — it pops up anchored right at the
        // tapped card, matching where the user's attention already is, instead of a
        // confirmationDialog's forced-to-the-bottom-of-the-screen system sheet.
        Menu {
            Button("Photo Library", systemImage: "photo") { photosPickerDocType = type }
            Button("Take Photo", systemImage: "camera") { cameraDocType = type }
            Button("Choose File", systemImage: "folder") { fileImporterDocType = type }
        } label: {
            documentCardLabel(icon: type.icon, title: title)
        }
        .disabled(isUploadingDocument)
    }

    /// Renders either a bundled asset (e.g. the boarding-pass glyph, tinted like an SF Symbol
    /// via `.renderingMode(.template)`) or a system symbol, from the same `FlightDocumentIcon`
    /// value — shared between the action cards and the uploaded-documents list row.
    private func flightDocumentIcon(_ icon: FlightDocumentIcon, size: CGFloat) -> some View {
        Group {
            switch icon {
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: size))
            }
        }
    }

    private func documentCardIcon(_ icon: FlightDocumentIcon) -> some View {
        ZStack {
            Circle().fill(Theme.skyBlue.opacity(0.15))
            flightDocumentIcon(icon, size: 20)
                .foregroundStyle(Theme.skyBlue)
        }
        .frame(width: 40, height: 40)
    }

    private func documentCardLabel(icon: FlightDocumentIcon, title: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            documentCardIcon(icon)

            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.sm)
        .background(
            Theme.cardBackground,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        )
    }

    private var tripNotesSheet: some View {
        NavigationStack {
            TextEditor(text: $tripNotesDraft)
                .padding(Theme.Spacing.sm)
                .navigationTitle("Trip checklist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { showingTripNotes = false } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            Task {
                                if var trip = linkedTrip {
                                    trip.notes = tripNotesDraft
                                    await appModel.updateTripNotes(trip)
                                }
                                showingTripNotes = false
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Notification preferences

    private var notificationPreferencesCard: some View {
        SectionCard {
            Text("Notify me about").font(.subheadline.weight(.semibold))
            Toggle("Gate & terminal changes", isOn: $gateTerminalChanges).font(.subheadline)
            Toggle("Delays & cancellations", isOn: $delayOrCancellation).font(.subheadline)
            Toggle("Departure", isOn: $departureNotif).font(.subheadline)
            Toggle("Landing", isOn: $landingNotif).font(.subheadline)
            Toggle("Arrival at gate", isOn: $arrivalAtGateNotif).font(.subheadline)
            Toggle("Baggage claim", isOn: $baggageClaimNotif).font(.subheadline)
        }
        .onChange(of: gateTerminalChanges) { _, _ in savePreferencesIfLoaded() }
        .onChange(of: delayOrCancellation) { _, _ in savePreferencesIfLoaded() }
        .onChange(of: departureNotif) { _, _ in savePreferencesIfLoaded() }
        .onChange(of: landingNotif) { _, _ in savePreferencesIfLoaded() }
        .onChange(of: arrivalAtGateNotif) { _, _ in savePreferencesIfLoaded() }
        .onChange(of: baggageClaimNotif) { _, _ in savePreferencesIfLoaded() }
    }

    private func savePreferencesIfLoaded() {
        guard preferencesLoaded, let userID = BackendService.currentUserID else { return }
        Task {
            try? await BackendService.upsertNotificationPreferences(FlightNotificationPreferences(
                flightID: flight.id, profileID: userID,
                gateTerminalChanges: gateTerminalChanges, delayOrCancellation: delayOrCancellation,
                departure: departureNotif, landing: landingNotif,
                arrivalAtGate: arrivalAtGateNotif, baggageClaimUpdate: baggageClaimNotif
            ))
        }
    }

    // MARK: - Legacy self-reported updates (only when traveler on a linked trip)

    private var legacyLogUpdateCard: some View {
        SectionCard {
            Text("Log an update").font(.subheadline.weight(.semibold))
            TextField("Add a note (optional)", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach([FlightUpdateKind.mealService, .disruption, .goingToSleep], id: \.self) { kind in
                    Button {
                        logSelfReportedUpdate(kind: kind)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.icon).font(.subheadline.weight(.semibold))
                            Text(kind.label).font(.caption2.weight(.medium)).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .foregroundStyle(.white)
                        .background(LinearGradient(colors: kind.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isSendingUpdate)
                }
            }
        }
    }

    private var legacyUpdatesCard: some View {
        SectionCard {
            Text("Their notes").font(.subheadline.weight(.semibold))
            ForEach(selfReportedUpdates) { update in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(colors: update.kind.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: update.kind.icon).foregroundStyle(.white).font(.caption)
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.kind.label).font(.subheadline.weight(.semibold))
                        if let note = update.note, !note.isEmpty {
                            Text(note).font(.caption).foregroundStyle(Theme.subtleInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(update.createdAt, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(Theme.subtleInk)
                }
            }
        }
    }

    private func logSelfReportedUpdate(kind: FlightUpdateKind) {
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = FlightUpdate(kind: kind, note: note.isEmpty ? kind.defaultNote : note)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            selfReportedUpdates.insert(update, at: 0)
        }
        noteDraft = ""
        isSendingUpdate = true
        Task {
            try? await BackendService.insertFlightUpdate(flightID: flight.id, kind: update.kind, note: update.note)
            isSendingUpdate = false
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
        // Premium-gated (see delayAnalysisCard) — skip the AeroAPI history call entirely for
        // Plus/free accounts rather than paying for a fetch nobody can see the result of.
        if !appModel.isPremiumLocked, let stats = try? await AeroFlightService.fetchDelayStats(flightID: flight.id) {
            delayStats = stats
        }
        if let prefs = try? await BackendService.fetchNotificationPreferences(flightID: flight.id) {
            gateTerminalChanges = prefs.gateTerminalChanges
            delayOrCancellation = prefs.delayOrCancellation
            departureNotif = prefs.departure
            landingNotif = prefs.landing
            arrivalAtGateNotif = prefs.arrivalAtGate
            baggageClaimNotif = prefs.baggageClaimUpdate
        }
        preferencesLoaded = true

        if linkedTrip != nil, let fetched = try? await BackendService.fetchFlightUpdates(flightID: flight.id) {
            selfReportedUpdates = fetched
        }

        let (channel, stream) = BackendService.subscribeToFlightStatusEvents(flightID: flight.id)
        eventsChannel = channel
        Task {
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
        Task {
            for await _ in flightUpdateStream {
                if let fresh = try? await BackendService.fetchFlight(id: flight.id) {
                    withAnimation(.easeInOut(duration: 0.3)) { flight = fresh }
                }
            }
        }

        await refreshFromProvider()
    }

    private func refreshFromProvider() async {
        guard !isRefreshing, flight.trackingEnabled, flight.faFlightID != nil else { return }
        isRefreshing = true
        try? await AeroFlightService.refreshFlight(id: flight.id)
        if let fresh = try? await BackendService.fetchFlight(id: flight.id) {
            flight = fresh
        }
        isRefreshing = false
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem, type: FlightDocumentType) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) else { return }
        await uploadImageDocument(uiImage, type: type)
        documentPickerItem = nil
    }

    private func uploadImageDocument(_ uiImage: UIImage, type: FlightDocumentType) async {
        let resized = uiImage.resized(maxDimension: 2000)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
        isUploadingDocument = true
        if let document = try? await BackendService.insertFlightDocument(
            coupleID: appModel.couple.id, flightID: flight.id, tripID: nil,
            docType: type, data: jpeg, contentType: "image/jpeg", fileExtension: "jpg", originalFilename: nil
        ) {
            documents.insert(document, at: 0)
        }
        isUploadingDocument = false
    }

    /// Files (unlike the Photos/camera paths) can be anything the user picked — a PDF boarding
    /// pass, a `.pkpass`, whatever — so this uploads the raw bytes as-is rather than forcing a
    /// decode through `UIImage`.
    private func uploadFileDocument(at url: URL, type: FlightDocumentType) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let fileExtension = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let contentType = UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream"
        isUploadingDocument = true
        if let document = try? await BackendService.insertFlightDocument(
            coupleID: appModel.couple.id, flightID: flight.id, tripID: nil,
            docType: type, data: data, contentType: contentType, fileExtension: fileExtension, originalFilename: url.lastPathComponent
        ) {
            documents.insert(document, at: 0)
        }
        isUploadingDocument = false
    }

    private static func relativeShort(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now).replacingOccurrences(of: "in ", with: "").replacingOccurrences(of: " ago", with: "")
    }
}

#Preview {
    NavigationStack {
        FlightTrackingView(flight: MockData.reunionTrip.flight ?? MockData.activeFlight)
    }
    .environment(AppModel())
}
