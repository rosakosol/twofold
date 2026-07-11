//
//  AddFlightView.swift
//  Twofold
//
//  Real AeroAPI-backed flight search (via the resolve-flight Edge Function — the API key never
//  touches this client). Two ways in, matching the reference interaction pattern but in
//  Twofold's own visual language: search by flight number, or by route. Selecting a result
//  opens a confirmation step (link to a trip, notifications) before it's actually persisted
//  and tracked, via add-flight.
//

import SwiftUI

struct AddFlightView: View {
    private enum SearchMode: String, CaseIterable {
        case flightNumber = "Find by Flight Number"
        case route = "Find by Route"

        enum Icon {
            case system(String)
            case asset(String)
        }

        var icon: Icon {
            switch self {
            case .flightNumber:
                return .asset("boarding-pass") // Assets.xcassets
            case .route:
                return .system("arrow.triangle.swap")
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchMode: SearchMode = .flightNumber
    @State private var flightNumber = ""
    @State private var originHint = ""
    @State private var routeOrigin = ""
    @State private var routeDestination = ""
    @State private var date = Date.now

    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var searchError: String?
    @State private var candidates: [AeroFlightCandidate] = []
    @State private var selectedCandidate: AeroFlightCandidate?

    /// Any real IATA (3-letter) or ICAO (4-letter) airport code — AeroAPI itself accepts either,
    /// so this isn't limited to Twofold's own curated `Place.commonCities` list the way an
    /// in-app city picker would be.
    private func isValidAirportCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return (3...4).contains(trimmed.count) && trimmed.allSatisfy(\.isLetter)
    }

    private var canSearch: Bool {
        switch searchMode {
        case .flightNumber: !flightNumber.trimmingCharacters(in: .whitespaces).isEmpty
        case .route: isValidAirportCode(routeOrigin) && isValidAirportCode(routeDestination)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Add a flight")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Airline, airport, or flight number")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        modeRow(.flightNumber)
                        modeRow(.route)
                    }

                    inputSection

                    Button(action: search) {
                        HStack {
                            if isSearching { ProgressView().tint(.white) }
                            Text(isSearching ? "Searching…" : "Search")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundStyle(.white)
                        .background(canSearch ? Theme.primaryButtonGradient : LinearGradient(colors: [Theme.subtleInk, Theme.subtleInk], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .disabled(!canSearch || isSearching)

                    resultsSection
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedCandidate) { candidate in
                FlightConfirmationView(candidate: candidate) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Mode selector

    private func modeRow(_ mode: SearchMode) -> some View {
        Button {
            searchMode = mode
            candidates = []
            hasSearched = false
            searchError = nil
        } label: {
            HStack {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    modeIcon(mode.icon)
                        .foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 36, height: 36)
                Text(mode.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if searchMode == mode {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leafGreen)
                }
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func modeIcon(_ icon: SearchMode.Icon) -> some View {
        switch icon {
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        case .system(let name):
            Image(systemName: name)
        }
    }

    // MARK: - Inputs

    @ViewBuilder
    private var inputSection: some View {
        switch searchMode {
        case .flightNumber:
            VStack(spacing: Theme.Spacing.sm) {
                TextField("Qantas, MEL, or QF123", text: $flightNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                DatePicker("Departure date", selection: $date, displayedComponents: [.date])
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                airportCodeField("Origin (optional) — e.g. MEL or YMML", text: $originHint)
            }
        case .route:
            VStack(spacing: Theme.Spacing.sm) {
                airportCodeField("From — e.g. MEL or YMML", text: $routeOrigin)
                airportCodeField("To — e.g. SIN or WSSS", text: $routeDestination)
                DatePicker("Departure date", selection: $date, displayedComponents: [.date])
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }

    private func airportCodeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsSection: some View {
        if let searchError {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(Theme.heartRed)
                Text(searchError).font(.subheadline).foregroundStyle(Theme.subtleInk).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
        } else if hasSearched, candidates.isEmpty, !isSearching {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "airplane.circle").font(.title).foregroundStyle(Theme.subtleInk)
                Text("No flights found for that date").font(.subheadline.weight(.medium))
                Text("Double-check the flight number or try a nearby date.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
        } else if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(candidates.count == 1 ? "1 match" : "\(candidates.count) matches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                ForEach(candidates) { candidate in
                    candidateCard(candidate)
                }
            }
        }
    }

    private func candidateCard(_ candidate: AeroFlightCandidate) -> some View {
        Button {
            selectedCandidate = candidate
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    AirlineLogoView(url: candidate.logoURL, size: 22)
                    Text(candidate.displayFlightNumber).font(.headline)
                    if candidate.isCodeshare == true {
                        PillBadge(text: "Codeshare", tint: Theme.subtleInk)
                    }
                    Spacer()
                    if let status = candidate.status.flatMap(FlightStatus.init(rawValue:)) {
                        PillBadge(text: status.displayLabel, tint: status.semanticColor)
                    }
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Text(candidate.origin?.iata ?? candidate.origin?.icao ?? "—")
                    Image(systemName: "arrow.right")
                    Text(candidate.destination?.iata ?? candidate.destination?.icao ?? "—")
                }
                .font(.subheadline.weight(.semibold))

                if let originCity = candidate.origin?.city, let destinationCity = candidate.destination?.city {
                    Text("\(originCity) → \(destinationCity)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }

                HStack(spacing: Theme.Spacing.xs) {
                    if let out = candidate.scheduledOut {
                        let originTZ: TimeZone = candidate.origin?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
                        Text(out, format: Date.FormatStyle(timeZone: originTZ).hour().minute())
                    }
                    if candidate.scheduledOut != nil, candidate.scheduledIn != nil {
                        Image(systemName: "arrow.right").font(.caption2)
                    }
                    if let arrival = candidate.scheduledIn {
                        let destinationTZ: TimeZone = candidate.destination?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
                        Text(arrival, format: Date.FormatStyle(timeZone: destinationTZ).hour().minute())
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func search() {
        isSearching = true
        searchError = nil
        Task {
            do {
                let trimmedOriginHint = originHint.trimmingCharacters(in: .whitespaces)
                switch searchMode {
                case .flightNumber:
                    candidates = try await AeroFlightService.searchByFlightNumber(flightNumber, date: date, originIata: trimmedOriginHint.isEmpty ? nil : trimmedOriginHint)
                case .route:
                    let originCode = routeOrigin.trimmingCharacters(in: .whitespaces)
                    let destinationCode = routeDestination.trimmingCharacters(in: .whitespaces)
                    candidates = try await AeroFlightService.searchByRoute(originIata: originCode, destinationIata: destinationCode, date: date)
                }
            } catch {
                searchError = (error as? AeroFlightError)?.errorDescription ?? "Something went wrong. Try again."
            }
            hasSearched = true
            isSearching = false
        }
    }
}

/// Confirmation step — link to a trip, decide on notifications, then actually starts tracking
/// via `add-flight`.
private struct FlightConfirmationView: View {
    let candidate: AeroFlightCandidate
    var onDone: () -> Void

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var linkedTripID: Trip.ID?
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
                try await AeroFlightService.addFlight(faFlightId: candidate.faFlightId, tripID: linkedTripID, notifyMe: notifyMe)
                await appModel.refreshFlights()
                onDone()
            } catch {
                errorMessage = (error as? AeroFlightError)?.errorDescription ?? "Couldn't save that flight. Try again."
                isSaving = false
            }
        }
    }
}

#Preview {
    AddFlightView()
        .environment(AppModel())
}
