//
//  AddFlightRouteStepView.swift
//  Twofold
//
//  Route search on a single screen: both ends visible at once, either one editable at any time.
//  This replaces a two-step departure-then-destination push, where a departure chosen three
//  screens back could only be corrected by walking the whole flow backwards — and where you
//  could never see the route you had actually built until the results arrived.
//
//  One suggestion list serves both fields; it belongs to whichever field holds focus. That is
//  what makes the single screen work, and it's why `focusedField` is part of the search key
//  rather than just the query text — moving focus is itself a new search.
//
//  Typing matches IATA/ICAO codes, airport names and city names together, because
//  `FlightSearchIndex.searchAirports` already queries `city`. So "Melbourne" lists Melbourne
//  Intl *and* Avalon rather than requiring someone to know that Avalon is a Melbourne airport —
//  which is the whole point of letting a city be a valid thing to type.
//

import SwiftUI
import PostHog

struct AddFlightRouteStepView: View {
    @Environment(AddFlightFlowModel.self) private var model

    @State private var departureQuery = ""
    @State private var destinationQuery = ""
    @State private var results: [Airport] = []
    @State private var isSearching = false
    @FocusState private var focusedField: AirportRole?

    /// Focus plus that field's text. `.task(id:)` on this gives debounce and cancellation for
    /// typing *and* re-runs the lookup when focus moves between the two fields.
    private struct SearchKey: Equatable {
        let role: AirportRole?
        let query: String
    }

    private var searchKey: SearchKey {
        SearchKey(role: focusedField, query: activeQuery)
    }

    private var activeQuery: String {
        switch focusedField {
        case .departure: departureQuery
        case .destination: destinationQuery
        case nil: ""
        }
    }

    private var canContinue: Bool {
        model.departureAirport != nil && model.destinationAirport != nil
    }

    var body: some View {
        AddFlightStepScaffold(subtitle: "Where are you flying?") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                routeCard
                suggestions
                continueButton
            }
        }
        .task(id: searchKey) {
            await performSearch()
        }
        .onAppear(perform: restoreFromModel)
        .postHogScreenView("Flights: Add Flight — Route")
    }

    // MARK: - Route card

    private var routeCard: some View {
        VStack(spacing: 0) {
            airportField(role: .departure)
            Divider().padding(.leading, 44)
            airportField(role: .destination)
        }
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        // Centred on the divider between the two fields, which is the only place a swap control
        // reads as belonging to both of them.
        .overlay(alignment: .trailing) {
            swapButton.padding(.trailing, Theme.Spacing.md)
        }
        // Editing the text invalidates the airport that text was standing for. Without this,
        // typing over a chosen "MEL · Melbourne" would leave MEL as the departure while the
        // field on screen said something else entirely.
        .onChange(of: departureQuery) { _, new in
            if let departure = model.departureAirport, new != Self.displayText(for: departure) {
                model.departureAirport = nil
            }
        }
        .onChange(of: destinationQuery) { _, new in
            if let destination = model.destinationAirport, new != Self.displayText(for: destination) {
                model.destinationAirport = nil
            }
        }
    }

    private func airportField(role: AirportRole) -> some View {
        let isDeparture = role == .departure
        let airport = isDeparture ? model.departureAirport : model.destinationAirport

        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isDeparture ? "airplane.departure" : "airplane.arrival")
                .font(.subheadline)
                .foregroundStyle(airport == nil ? Theme.subtleInk : Theme.skyBlue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDeparture ? "FROM" : "TO")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)

                TextField(
                    isDeparture ? "City or airport code" : "Where to?",
                    text: isDeparture ? $departureQuery : $destinationQuery
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(isDeparture ? .next : .search)
                .focused($focusedField, equals: role)
                .foregroundStyle(Theme.ink)
                .onSubmit { submit(from: role) }
            }

            // Room for the swap button, which sits over this edge of the card.
            Spacer(minLength: 48)
        }
        .padding(Theme.Spacing.md)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = role }
    }

    private var swapButton: some View {
        let hasEither = model.departureAirport != nil || model.destinationAirport != nil
        return Button(action: swapEnds) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.skyBlue)
                .frame(width: 32, height: 32)
                .background(Theme.skyBlue.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!hasEither)
        .opacity(hasEither ? 1 : 0.4)
        .accessibilityLabel("Swap departure and destination")
    }

    // MARK: - Suggestions

    /// Named for what the list actually is, which changes with focus: the default list for a
    /// destination is where you'd plausibly fly *from the departure already chosen*, not a
    /// generic set of airports, and calling both "suggestions" hid that.
    private var suggestionsHeader: String {
        guard activeQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return "SUGGESTIONS" }
        return focusedField == .destination && model.departureAirport != nil ? "COMMON DESTINATIONS" : "NEARBY"
    }

    @ViewBuilder
    private var suggestions: some View {
        if isSearching {
            ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.lg)
        } else if focusedField != nil, !results.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(suggestionsHeader)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)

                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(results) { airport in
                        suggestionRow(airport)
                    }
                }
            }
        } else if focusedField != nil {
            let hasTyped = !activeQuery.trimmingCharacters(in: .whitespaces).isEmpty
            VStack(spacing: Theme.Spacing.xs) {
                Text(hasTyped ? "No airports match that" : "Search for an airport")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text("Type a city, an airport name, or its three-letter code.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
        }
    }

    /// Leads with the IATA code rather than a generic airplane glyph: the code is the thing
    /// you'd have typed, and it's what tells two airports in the same city apart at a glance.
    private func suggestionRow(_ airport: Airport) -> some View {
        Button {
            select(airport)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(airport.preferredCode ?? "—")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.skyBlue)
                    .frame(width: 44)
                    .padding(.vertical, 6)
                    .background(Theme.skyBlue.opacity(0.15), in: Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(airport.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text([airport.cityOrName, airport.country].compactMap { $0 }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCardBackground(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Continue

    /// Always present, and it says what it is still waiting for. Both ends are optional-until-
    /// chosen and either one can be the missing one, so a button that only appeared when the
    /// route was complete would leave someone with a half-filled card and nothing to read.
    private var continueLabel: String {
        switch (model.departureAirport, model.destinationAirport) {
        case (nil, nil): "Pick both airports"
        case (nil, _): "Pick a departure airport"
        case (_, nil): "Pick a destination"
        default: "Pick a date"
        }
    }

    private var continueButton: some View {
        Button {
            focusedField = nil
            model.path.append(.date)
        } label: {
            Text(continueLabel)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.5)
    }

    // MARK: - Actions

    /// The text a committed airport puts in its field. Also how `performSearch` recognises that
    /// a field is showing a selection rather than a half-typed query.
    private static func displayText(for airport: Airport) -> String {
        "\(airport.preferredCode ?? airport.iata) · \(airport.cityOrName)"
    }

    private func restoreFromModel() {
        // Coming back from the date step, or in from the entry screen's airport suggestion —
        // either way the model may already hold ends this screen has never rendered.
        if let departure = model.departureAirport, departureQuery.isEmpty {
            departureQuery = Self.displayText(for: departure)
        }
        if let destination = model.destinationAirport, destinationQuery.isEmpty {
            destinationQuery = Self.displayText(for: destination)
        }
        // Open on the end that still needs answering.
        if model.departureAirport == nil {
            focusedField = .departure
        } else if model.destinationAirport == nil {
            focusedField = .destination
        }
    }

    private func select(_ airport: Airport) {
        // Model first, then the field text: the `onChange` guards compare the new text against
        // the committed airport, and doing it the other way round clears what was just chosen.
        if focusedField == .destination {
            model.destinationAirport = airport
            destinationQuery = Self.displayText(for: airport)
            focusedField = model.departureAirport == nil ? .departure : nil
        } else {
            model.departureAirport = airport
            departureQuery = Self.displayText(for: airport)
            focusedField = model.destinationAirport == nil ? .destination : nil
        }
        results = []
    }

    private func submit(from role: AirportRole) {
        switch role {
        case .departure:
            focusedField = .destination
        case .destination:
            guard canContinue else { return }
            focusedField = nil
            model.path.append(.date)
        }
    }

    private func swapEnds() {
        let departure = model.departureAirport
        model.departureAirport = model.destinationAirport
        model.destinationAirport = departure
        swap(&departureQuery, &destinationQuery)
    }

    private func performSearch() async {
        guard let role = focusedField else {
            results = []
            isSearching = false
            return
        }

        let committed = role == .departure ? model.departureAirport : model.destinationAirport
        let typed = role == .departure ? departureQuery : destinationQuery
        // A field showing its own committed selection is not a search. Treated as empty so that
        // re-focusing a filled field offers the default list again, instead of looking up
        // "MEL · Melbourne" and coming back with nothing.
        let query = committed.map { typed == Self.displayText(for: $0) } == true ? "" : typed

        if !query.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        isSearching = true

        // Excludes whichever end is already chosen, in both directions — a route needs two
        // different airports, and editing the departure should no more offer the chosen
        // destination than the other way round.
        let other = role == .departure ? model.destinationAirport : model.departureAirport
        let fetched: [Airport]
        if query.trimmingCharacters(in: .whitespaces).isEmpty,
           role == .destination,
           let departure = model.departureAirport {
            fetched = (try? await FlightSearchIndex.domesticDestinations(from: departure, limit: 10)) ?? []
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty, model.nearCoordinate == nil {
            // Nothing typed and no proximity signal to rank by — `searchAirports("")` would hand
            // back whichever ten of ~6,000 rows Postgres happened to return first, which is how
            // the old screen came to open on Alexandra, New Zealand. A home city is optional
            // (and absent for most of onboarding), so this is a normal state, not an edge case:
            // ask for a search rather than answer with an arbitrary list.
            fetched = []
        } else {
            fetched = (try? await FlightSearchIndex.searchAirports(query, near: model.nearCoordinate, excluding: other, limit: 10)) ?? []
        }

        guard !Task.isCancelled else { return }
        results = fetched
        isSearching = false
    }
}
