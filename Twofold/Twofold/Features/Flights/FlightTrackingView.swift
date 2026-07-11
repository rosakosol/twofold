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

struct FlightTrackingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var flight: Flight
    @State private var events: [FlightStatusEvent] = []
    @State private var showAllEvents = false
    @State private var documents: [FlightDocument] = []
    @State private var isRefreshing = false
    @State private var eventsChannel: RealtimeChannelV2?

    // Notification preferences — individually-bound so the toggles feel instant; saved as one
    // upsert on change.
    @State private var gateTerminalChanges = true
    @State private var delayOrCancellation = true
    @State private var departureNotif = true
    @State private var landingNotif = true
    @State private var arrivalAtGateNotif = true
    @State private var baggageClaimNotif = true
    @State private var preferencesLoaded = false

    // Document upload
    @State private var pendingDocType: FlightDocumentType?
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

    private var isTraveler: Bool {
        guard let linkedTrip else { return false }
        return appModel.currentUser.id == linkedTrip.travelerID
    }

    private var traveler: Person? {
        linkedTrip.flatMap { appModel.couple.partner($0.travelerID) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                mapSection
                journeyCard
                departureCard
                arrivalCard
                updatesCard
                flightInfoCard
                goodToKnowCard
                documentsSection
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
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(traveler.map { "\($0.name)'s journey" } ?? "Flight \(flight.displayNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task { await loadEverything() }
        .refreshable { await refreshFromProvider() }
        .onDisappear {
            if let eventsChannel { Task { await BackendService.unsubscribe(eventsChannel) } }
            if let selfReportChannel { Task { await BackendService.unsubscribe(selfReportChannel) } }
        }
        .sheet(isPresented: $showingTripNotes) {
            tripNotesSheet
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("\(flight.origin.displayName) → \(flight.destination.displayName)")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)

            if flight.airlineName != nil || !flight.flightNumberIATA.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    AirlineLogoView(url: flight.displayLogoURL, size: 20)
                    Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
                if flight.isDelayed, flight.status != .cancelled {
                    Image(systemName: flight.status.icon).font(.caption2).foregroundStyle(Theme.heartRed)
                }
            }

            Text(flight.countdownSummary)
                .font(.title2.weight(.bold))

            if flight.lastRefreshedAt != nil {
                Text("Updated \(flight.lastRefreshedAt.map(Self.relativeShort) ?? "recently")")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var shareText: String {
        "\(flight.displayNumber) · \(flight.origin.displayCode) → \(flight.destination.displayCode) — \(flight.countdownSummary)"
    }

    // MARK: - Map

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            FlightMapView(flight: flight)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            if flight.hasLivePosition {
                HStack(spacing: Theme.Spacing.sm) {
                    if let altitude = flight.positionAltitude {
                        StatTile(icon: "arrow.up.to.line", value: "\(Int(altitude))ft", label: "Altitude", tint: Theme.skyBlue)
                    }
                    if let speed = flight.positionGroundspeed {
                        StatTile(icon: "speedometer", value: "\(Int(speed))kn", label: "Speed", tint: Theme.skyBlue)
                    }
                    if let heading = flight.positionHeading {
                        StatTile(icon: "safari", value: "\(Int(heading))°", label: "Heading", tint: Theme.skyBlue)
                    }
                }
            }
        }
    }

    // MARK: - Journey summary

    private var journeyCard: some View {
        SectionCard {
            journeyRow(
                code: flight.origin.displayCode, city: flight.origin.displayName,
                time: flight.bestDeparture, timeZone: flight.origin.timeZone,
                terminal: flight.terminalOrigin, gate: flight.gateOrigin,
                statusLine: departureStatusLine
            )

            HStack {
                Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(width: 2, height: 28).padding(.leading, 15)
                Spacer()
            }

            journeyRow(
                code: flight.destination.displayCode, city: flight.destination.displayName,
                time: flight.bestArrival, timeZone: flight.destination.timeZone,
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
                    Text(time, format: Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute())
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

    private var departureCard: some View {
        SectionCard {
            Text("Departure").font(.subheadline.weight(.semibold))
            detailRow(label: "Airport", value: "\(flight.origin.displayCode) · \(flight.origin.displayName)")
            detailRow(label: "Scheduled", value: Self.timeOrNA(flight.scheduledOut, timeZone: flight.origin.timeZone))
            detailRow(label: flight.actualOut != nil ? "Actual" : "Estimated", value: Self.timeOrNA(flight.actualOut ?? flight.estimatedOut, timeZone: flight.origin.timeZone))
            if let delaySeconds = flight.departureDelaySeconds, delaySeconds > 300 {
                detailRow(label: "Status", value: "Delayed \(delaySeconds / 60) min", tint: Theme.heartRed)
            }
            detailRow(label: "Terminal", value: flight.terminalOrigin ?? "Not available")
            detailRow(label: "Gate", value: flight.gateOrigin ?? "Not available")
            weatherRow(flight.weatherOrigin)
        }
    }

    private var arrivalCard: some View {
        SectionCard {
            Text("Arrival").font(.subheadline.weight(.semibold))
            detailRow(label: "Airport", value: "\(flight.destination.displayCode) · \(flight.destination.displayName)")
            detailRow(label: "Scheduled", value: Self.timeOrNA(flight.scheduledIn, timeZone: flight.destination.timeZone))
            detailRow(label: flight.actualIn != nil ? "Actual" : "Estimated", value: Self.timeOrNA(flight.actualIn ?? flight.estimatedIn, timeZone: flight.destination.timeZone))
            if let delaySeconds = flight.arrivalDelaySeconds, delaySeconds > 300 {
                detailRow(label: "Status", value: "Delayed \(delaySeconds / 60) min", tint: Theme.heartRed)
            }
            detailRow(label: "Terminal", value: flight.terminalDestination ?? "Not available")
            detailRow(label: "Gate", value: flight.gateDestination ?? "Not available")
            detailRow(label: "Baggage claim", value: flight.baggageClaim ?? "Not available")
            weatherRow(flight.weatherDestination)
        }
    }

    private func detailRow(label: String, value: String, tint: Color = Theme.ink) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(Theme.subtleInk)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(tint)
        }
    }

    @ViewBuilder
    private func weatherRow(_ weather: FlightWeather?) -> some View {
        if let weather, !weather.isEmpty {
            detailRow(label: "Weather", value: [weather.conditions, weather.temperatureC.map { "\(Int($0))°C" }, weather.windSummary].compactMap { $0 }.joined(separator: " · "))
        } else {
            detailRow(label: "Weather", value: "Not available")
        }
    }

    private static func timeOrNA(_ date: Date?, timeZone: TimeZone?) -> String {
        guard let date else { return "Not available" }
        return date.formatted(Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute())
    }

    // MARK: - Updates timeline

    private var updatesCard: some View {
        SectionCard {
            HStack {
                Text("Flight updates").font(.subheadline.weight(.semibold))
                Spacer()
                if events.count > 4 {
                    Button(showAllEvents ? "Show less" : "Show all") { showAllEvents.toggle() }
                        .font(.caption.weight(.medium))
                }
            }

            if events.isEmpty {
                Text("No updates yet — we'll show gate changes, delays, and milestones here as they happen.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                ForEach(showAllEvents ? events : Array(events.prefix(4))) { event in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ZStack {
                            Circle().fill(event.type.isUrgent ? Theme.heartRed.opacity(0.15) : Theme.skyBlue.opacity(0.15))
                            Image(systemName: event.type.icon).font(.caption).foregroundStyle(event.type.isUrgent ? Theme.heartRed : Theme.skyBlue)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.label).font(.subheadline.weight(.medium))
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
            SectionCard {
                Text("Flight information").font(.subheadline.weight(.semibold))
                detailRow(label: "Aircraft", value: flight.aircraftType ?? "Not available")
                detailRow(label: "Registration", value: flight.registration ?? "Not available")
            }
        }
    }

    // MARK: - Good to know

    private var goodToKnowCard: some View {
        SectionCard {
            Text("Good to know").font(.subheadline.weight(.semibold))
            if let timezoneCopy {
                Text(timezoneCopy).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            if let arrivalInHomeTZCopy {
                Text(arrivalInHomeTZCopy).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            if flight.weatherOrigin == nil && flight.weatherDestination == nil && timezoneCopy == nil {
                Text("Once this flight is actively tracked, weather and timezone context will show up here.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
    }

    private var timezoneCopy: String? {
        guard let originTZ = flight.origin.timeZone, let destinationTZ = flight.destination.timeZone, originTZ != destinationTZ else { return nil }
        let now = Date.now
        let diffSeconds = destinationTZ.secondsFromGMT(for: now) - originTZ.secondsFromGMT(for: now)
        let diffHours = diffSeconds / 3600
        guard diffHours != 0 else { return nil }
        let direction = diffHours > 0 ? "ahead of" : "behind"
        return "\(flight.destination.displayName) is \(abs(diffHours)) hour\(abs(diffHours) == 1 ? "" : "s") \(direction) \(flight.origin.displayName)."
    }

    private var arrivalInHomeTZCopy: String? {
        guard let arrival = flight.bestArrival, let destinationTZ = flight.destination.timeZone, let homeTZ = appModel.currentUser.homeCity?.timeZone, destinationTZ != homeTZ else { return nil }
        let destinationTime = arrival.formatted(Date.FormatStyle(timeZone: destinationTZ).hour().minute())
        let homeTime = arrival.formatted(Date.FormatStyle(timeZone: homeTZ).hour().minute())
        return "\(destinationTime) arrival is \(homeTime) for you."
    }

    // MARK: - Documents

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Trip preparation").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    documentActionCard(type: .boardingPass, title: "Boarding pass")
                    documentActionCard(type: .itinerary, title: "Travel documents")
                    if linkedTrip != nil {
                        Button {
                            tripNotesDraft = linkedTrip?.notes ?? ""
                            showingTripNotes = true
                        } label: {
                            documentCardLabel(icon: .system("checklist"), title: "Trip checklist")
                        }
                        .buttonStyle(.plain)
                    }
                }
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
        .photosPicker(isPresented: Binding(get: { pendingDocType != nil }, set: { if !$0 { pendingDocType = nil } }), selection: $documentPickerItem, matching: .images)
        .onChange(of: documentPickerItem) { _, newItem in
            guard let newItem, let docType = pendingDocType else { return }
            Task { await uploadDocument(item: newItem, type: docType) }
        }
    }

    private func documentActionCard(type: FlightDocumentType, title: String) -> some View {
        Button {
            pendingDocType = type
        } label: {
            documentCardLabel(icon: type.icon, title: title)
        }
        .buttonStyle(.plain)
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

    private func documentCardLabel(icon: FlightDocumentIcon, title: String) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                flightDocumentIcon(icon, size: 20)
                    .foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 40, height: 40)

            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
        }
        .frame(width: 92)
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

    private func uploadDocument(item: PhotosPickerItem, type: FlightDocumentType) async {
        pendingDocType = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) else { return }
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
        documentPickerItem = nil
    }

    private static func relativeShort(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now).replacingOccurrences(of: "in ", with: "").replacingOccurrences(of: " ago", with: "")
    }
}

#Preview {
    NavigationStack {
        FlightTrackingView(flight: MockData.reunionTrip.flight ?? Flight(selfReportedNumber: "QF9", origin: MockData.melbourne, destination: MockData.singapore, scheduledDeparture: .now, scheduledArrival: .now.addingTimeInterval(3600 * 8)))
    }
    .environment(AppModel())
}
