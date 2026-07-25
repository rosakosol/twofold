//
//  ExportHistoryView.swift
//  Twofold
//
//  Premium-only: lets someone pick exactly which trips/memories/(standalone) flights go into a
//  keepsake PDF, edit each one's description inline (the real `Trip.notes`/`Memory.note` fields —
//  editing here persists back to the actual record via `AppModel.updateTripNotes`/`updateMemory`,
//  the same functions Trip/Memory Details already call), and for flights, whether to include
//  their attached documents (boarding passes, itineraries — see `FlightDocument`). Reached from
//  Settings; gated by `appModel.isPremiumLocked` at the call site.
//

import SwiftUI
import PostHog

struct ExportHistoryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var selectedTripIDs: Set<UUID> = []
    @State private var selectedMemoryIDs: Set<UUID> = []
    @State private var selectedFlightIDs: Set<UUID> = []

    @State private var tripDescriptions: [UUID: String] = [:]
    @State private var memoryDescriptions: [UUID: String] = [:]
    /// Snapshots of `tripDescriptions`/`memoryDescriptions` as seeded, so `persistEditedDescriptions()`
    /// can tell "the user actually typed something here" apart from "the live `trip.notes`/
    /// `memory.note` changed underneath this screen" (e.g. the partner edited it elsewhere while
    /// this screen was open and a background refresh replaced `appModel.trips`/`memories`).
    /// Comparing the edit buffer against the live model value instead of this snapshot would
    /// treat that drift as a user edit and write the screen's stale cached text back over the
    /// partner's real change.
    @State private var originalTripDescriptions: [UUID: String] = [:]
    @State private var originalMemoryDescriptions: [UUID: String] = [:]

    @State private var flightAttachments: [UUID: [FlightDocument]] = [:]
    @State private var includeAttachments: [UUID: Bool] = [:]
    @State private var loadingAttachmentsFor: Set<UUID> = []

    @State private var expandedIDs: Set<UUID> = []

    @State private var isGenerating = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    private var trips: [Trip] {
        appModel.trips.sorted { $0.departureDate < $1.departureDate }
    }

    /// Every memory, trip-linked or not — the source of truth for selection/description state,
    /// since a trip-linked memory still needs both. Use `standaloneMemories` for the flat
    /// top-level "Memories" section, which only lists ones with nowhere else to nest under.
    private var memories: [Memory] {
        appModel.memories.sorted { $0.date < $1.date }
    }

    /// Trip-linked memories are shown nested under their own trip's row instead — excluded here
    /// so the same memory never appears twice in the list, mirroring `standaloneFlights` below.
    private var standaloneMemories: [Memory] {
        memories.filter { $0.tripID == nil }
    }

    /// Flights linked to a trip (`Flight.tripID` set) are shown nested under that trip's own row
    /// instead — only flights with no trip get their own top-level selectable entry, so the same
    /// flight never appears twice in the exported document.
    private var standaloneFlights: [Flight] {
        appModel.flights.filter { $0.tripID == nil }.sorted { ($0.bestDeparture ?? .distantPast) < ($1.bestDeparture ?? .distantPast) }
    }

    private func linkedMemories(for trip: Trip) -> [Memory] {
        memories.filter { $0.tripID == trip.id }
    }

    private var selectedCount: Int {
        selectedTripIDs.count + selectedMemoryIDs.count + selectedFlightIDs.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if trips.isEmpty && standaloneMemories.isEmpty && standaloneFlights.isEmpty {
                    emptyState
                } else {
                    if !trips.isEmpty {
                        section(title: "Trips", systemImage: "airplane") {
                            ForEach(trips) { trip in
                                tripRow(trip)
                            }
                        }
                    }
                    if !standaloneMemories.isEmpty {
                        section(title: "Memories", systemImage: "heart.fill") {
                            ForEach(standaloneMemories) { memory in
                                memoryRow(memory)
                            }
                        }
                    }
                    if !standaloneFlights.isEmpty {
                        section(title: "Flights", systemImage: "airplane.circle.fill") {
                            ForEach(standaloneFlights) { flight in
                                flightRow(flight)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .padding(.bottom, 100)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Export Your Story")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear(perform: seedSelectionsIfNeeded)
        .postHogScreenView("Settings: Export History")
    }

    // MARK: - Sections

    private func section<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
            VStack(spacing: Theme.Spacing.sm) {
                content()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 40))
                .foregroundStyle(Theme.subtleInk.opacity(0.4))
            Text("Nothing to export yet")
                .font(.headline)
            Text("Add a trip, memory, or flight and it'll show up here.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.xl)
    }

    // MARK: - Trip row

    private func tripRow(_ trip: Trip) -> some View {
        let linkedFlights = trip.orderedFlights
        let tripMemories = linkedMemories(for: trip)

        return SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectionToggle(isOn: selectedTripIDs.contains(trip.id)) { toggleSelection($0, id: trip.id, set: &selectedTripIDs) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trip.origin.displayCity) → \(trip.destination.displayCity)").font(.subheadline.weight(.semibold))
                        Text(trip.departureDate, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    expandButton(id: trip.id)
                }
                if expandedIDs.contains(trip.id) {
                    descriptionEditor(text: bindingForTripDescription(trip.id))
                }
                // Linked flights/memories appear underneath their trip rather than as their own
                // top-level rows — they'll be bundled into the same section of the exported PDF
                // regardless of whether their own trip checkbox above is on, so leaving them
                // toggleable here (not just informational) still lets you drop just one leg or
                // one memory from an otherwise-included trip.
                if !linkedFlights.isEmpty || !tripMemories.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(linkedFlights) { flight in
                            linkedFlightRow(flight)
                        }
                        ForEach(tripMemories) { memory in
                            linkedMemoryRow(memory)
                        }
                    }
                }
            }
        }
    }

    private func linkedFlightRow(_ flight: Flight) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                selectionToggle(isOn: selectedFlightIDs.contains(flight.id)) {
                    toggleSelection($0, id: flight.id, set: &selectedFlightIDs)
                    if $0 { loadAttachmentsIfNeeded(flight) }
                }
                AirlineLogoView(url: flight.displayLogoURL, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(flight.displayNumber).font(.caption.weight(.semibold))
                    Text("\(flight.origin.displayCode) → \(flight.destination.displayCode)").font(.caption2).foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
            if selectedFlightIDs.contains(flight.id) {
                flightAttachmentsSection(flight)
                    .padding(.leading, 30)
            }
        }
        .padding(.leading, Theme.Spacing.lg)
    }

    private func linkedMemoryRow(_ memory: Memory) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            selectionToggle(isOn: selectedMemoryIDs.contains(memory.id)) { toggleSelection($0, id: memory.id, set: &selectedMemoryIDs) }
            MemoryPhotoView(memory: memory, cornerRadius: 6).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(memory.title).font(.caption.weight(.semibold))
                Text(memory.date, format: .dateTime.day().month(.abbreviated).year()).font(.caption2).foregroundStyle(Theme.subtleInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Theme.Spacing.lg)
    }

    // MARK: - Memory row

    private func memoryRow(_ memory: Memory) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectionToggle(isOn: selectedMemoryIDs.contains(memory.id)) { toggleSelection($0, id: memory.id, set: &selectedMemoryIDs) }
                    MemoryPhotoView(memory: memory, cornerRadius: 8)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(memory.title).font(.subheadline.weight(.semibold))
                        Text(memory.date, format: .dateTime.day().month(.abbreviated).year()).font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    expandButton(id: memory.id)
                }
                if expandedIDs.contains(memory.id) {
                    descriptionEditor(text: bindingForMemoryDescription(memory.id))
                }
            }
        }
    }

    // MARK: - Flight row

    private func flightRow(_ flight: Flight) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    selectionToggle(isOn: selectedFlightIDs.contains(flight.id)) {
                        toggleSelection($0, id: flight.id, set: &selectedFlightIDs)
                        if $0 { loadAttachmentsIfNeeded(flight) }
                    }
                    AirlineLogoView(url: flight.displayLogoURL, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flight.displayNumber).font(.subheadline.weight(.semibold))
                        Text("\(flight.origin.displayCode) → \(flight.destination.displayCode)").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    expandButton(id: flight.id)
                }
                if expandedIDs.contains(flight.id) {
                    flightAttachmentsSection(flight)
                }
            }
        }
    }

    @ViewBuilder
    private func flightAttachmentsSection(_ flight: Flight) -> some View {
        if loadingAttachmentsFor.contains(flight.id) {
            ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.Spacing.xs)
        } else if let documents = flightAttachments[flight.id], !documents.isEmpty {
            Toggle("Include attachments", isOn: Binding(
                get: { includeAttachments[flight.id] ?? true },
                set: { includeAttachments[flight.id] = $0 }
            ))
            .font(.caption.weight(.medium))
            .tint(Theme.skyBlue)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(documents) { document in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().fill(Theme.skyBlue.opacity(0.15))
                            flightDocumentIcon(document.docType.icon)
                        }
                        .frame(width: 36, height: 36)
                        Text(document.docType.label).font(.caption2).foregroundStyle(Theme.subtleInk)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            Text("No attachments on this flight.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func flightDocumentIcon(_ icon: FlightDocumentIcon) -> some View {
        Group {
            switch icon {
            case .system(let name):
                Image(systemName: name)
            case .asset(let name):
                Image(name).renderingMode(.template).resizable().scaledToFit().padding(8)
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(Theme.skyBlue)
    }

    // MARK: - Shared row pieces

    private func selectionToggle(isOn: Bool, action: @escaping (Bool) -> Void) -> some View {
        Button { action(!isOn) } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isOn ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
        }
        .buttonStyle(.plain)
    }

    private func expandButton(id: UUID) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedIDs.contains(id) { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
            }
        } label: {
            Image(systemName: expandedIDs.contains(id) ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
        .buttonStyle(.plain)
    }

    private func descriptionEditor(text: Binding<String>) -> some View {
        TextField("Add a description for this story…", text: text, axis: .vertical)
            .font(.subheadline)
            .lineLimit(3...6)
            .padding(Theme.Spacing.sm)
            .background(Theme.backgroundBottom.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleSelection(_ isOn: Bool, id: UUID, set: inout Set<UUID>) {
        if isOn { set.insert(id) } else { set.remove(id) }
    }

    private func bindingForTripDescription(_ id: UUID) -> Binding<String> {
        Binding(get: { tripDescriptions[id] ?? "" }, set: { tripDescriptions[id] = $0 })
    }

    private func bindingForMemoryDescription(_ id: UUID) -> Binding<String> {
        Binding(get: { memoryDescriptions[id] ?? "" }, set: { memoryDescriptions[id] = $0 })
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
            }
            if let exportedURL {
                ShareLink(
                    item: exportedURL,
                    preview: SharePreview("Our Story", image: Image(systemName: "doc.richtext.fill"))
                ) {
                    Text("Share PDF")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)
            } else {
                Button(action: generate) {
                    Group {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Text(selectedCount == 0 ? "Select at least one story" : "Generate PDF (\(selectedCount))")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(
                    selectedCount == 0 || isGenerating ? AnyShapeStyle(Theme.subtleInk.opacity(0.3)) : AnyShapeStyle(Theme.primaryButtonGradient),
                    in: Capsule()
                )
                .foregroundStyle(.white)
                .disabled(selectedCount == 0 || isGenerating)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            LinearGradient(
                stops: [.init(color: Theme.backgroundBottom.opacity(0), location: 0), .init(color: Theme.backgroundBottom, location: 0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Data

    private func seedSelectionsIfNeeded() {
        guard selectedTripIDs.isEmpty, selectedMemoryIDs.isEmpty, selectedFlightIDs.isEmpty else { return }
        selectedTripIDs = Set(trips.map(\.id))
        selectedMemoryIDs = Set(memories.map(\.id))
        // Every flight, not just standalone ones — a trip-linked flight is just as selectable/
        // exportable now, just shown nested under its trip's row instead of its own top-level one.
        selectedFlightIDs = Set(appModel.flights.map(\.id))
        for trip in trips {
            tripDescriptions[trip.id] = trip.notes ?? ""
            originalTripDescriptions[trip.id] = trip.notes ?? ""
        }
        for memory in memories {
            memoryDescriptions[memory.id] = memory.note
            originalMemoryDescriptions[memory.id] = memory.note
        }
        for flight in appModel.flights where selectedFlightIDs.contains(flight.id) {
            loadAttachmentsIfNeeded(flight)
        }
    }

    private func loadAttachmentsIfNeeded(_ flight: Flight) {
        guard flightAttachments[flight.id] == nil, !loadingAttachmentsFor.contains(flight.id) else { return }
        loadingAttachmentsFor.insert(flight.id)
        Task {
            let documents = (try? await BackendService.fetchFlightDocuments(flightID: flight.id)) ?? []
            flightAttachments[flight.id] = documents
            includeAttachments[flight.id] = true
            loadingAttachmentsFor.remove(flight.id)
        }
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        Task {
            await persistEditedDescriptions()

            var items: [ExportTimelineItem] = []
            for trip in trips where selectedTripIDs.contains(trip.id) {
                let linkedFlights: [ExportTimelineItem.LinkedFlight] = trip.orderedFlights
                    .filter { selectedFlightIDs.contains($0.id) }
                    .map { flight in
                        ExportTimelineItem.LinkedFlight(
                            flight: flight,
                            includeAttachments: includeAttachments[flight.id] ?? true,
                            attachments: flightAttachments[flight.id] ?? []
                        )
                    }
                let tripLinkedMemories: [ExportTimelineItem.LinkedMemory] = linkedMemories(for: trip)
                    .filter { selectedMemoryIDs.contains($0.id) }
                    .map { memory in
                        ExportTimelineItem.LinkedMemory(memory: memory, description: memoryDescriptions[memory.id] ?? "")
                    }
                items.append(.trip(
                    trip,
                    description: tripDescriptions[trip.id] ?? "",
                    linkedFlights: linkedFlights,
                    linkedMemories: tripLinkedMemories
                ))
            }
            for memory in standaloneMemories where selectedMemoryIDs.contains(memory.id) {
                items.append(.memory(memory, description: memoryDescriptions[memory.id] ?? ""))
            }
            for flight in standaloneFlights where selectedFlightIDs.contains(flight.id) {
                let documents = flightAttachments[flight.id] ?? []
                let include = includeAttachments[flight.id] ?? true
                items.append(.flight(flight, includeAttachments: include, attachments: documents))
            }

            do {
                exportedURL = try await CoupleHistoryPDFExporter.generate(
                    selfName: appModel.currentUser.name,
                    partnerName: appModel.partner.name,
                    selfPhotoURL: appModel.currentUser.avatarURL,
                    partnerPhotoURL: appModel.partner.avatarURL,
                    items: items
                )
                Analytics.capture(Analytics.Event.exportHistoryGenerated, properties: ["item_count": items.count])
            } catch {
                errorMessage = "Couldn't generate the PDF — try again."
            }
            isGenerating = false
        }
    }

    /// Only writes back the trip/memory records the user actually edited on this screen —
    /// checked against the seed-time snapshot (`originalTripDescriptions`/
    /// `originalMemoryDescriptions`), not the live `trip.notes`/`memory.note`, so a background
    /// refresh that changed the live value while this screen was open (e.g. the partner edited
    /// it elsewhere) is never mistaken for a local edit and overwritten.
    private func persistEditedDescriptions() async {
        for trip in trips where selectedTripIDs.contains(trip.id) {
            let edited = tripDescriptions[trip.id] ?? ""
            guard edited != (originalTripDescriptions[trip.id] ?? "") else { continue }
            var updated = trip
            updated.notes = edited
            await appModel.updateTripNotes(updated)
        }
        for memory in memories where selectedMemoryIDs.contains(memory.id) {
            let edited = memoryDescriptions[memory.id] ?? ""
            guard edited != (originalMemoryDescriptions[memory.id] ?? "") else { continue }
            var updated = memory
            updated.note = edited
            await appModel.updateMemory(updated)
        }
    }
}

#Preview {
    NavigationStack {
        ExportHistoryView()
    }
    .environment(AppModel())
}
