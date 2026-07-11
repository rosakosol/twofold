//
//  AddFlightView.swift
//  Twofold
//
//  Attaches a flight number to one of the couple's existing trips that doesn't have one yet —
//  there's no real flight-schedule lookup API in this app (only forwarded-email parsing, a
//  different feature), so this doesn't pretend to search a live airline database. "Find by
//  Route"/"Find by Flight Number" both resolve to that same real capability, just entered
//  from two different natural starting points, the way a real flight search's chrome usually
//  offers both without this app inventing data neither can actually back.
//

import SwiftUI

struct AddFlightView: View {
    private enum SearchMode: String, CaseIterable {
        case flightNumber = "Find by Flight Number"
        case route = "Find by Route"

        var icon: String {
            switch self {
            case .flightNumber: "ticket.fill"
            case .route: "arrow.triangle.swap"
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchMode: SearchMode = .flightNumber
    @State private var query = ""
    @State private var routeOrigin: Place?
    @State private var routeDestination: Place?
    @State private var selectedTripID: Trip.ID?
    @State private var flightNumber = ""
    @State private var showingAddTrip = false
    @State private var isSaving = false

    private var tripsWithoutFlight: [Trip] {
        appModel.trips.filter { $0.flight == nil }
    }

    private var suggestedTrips: [Trip] {
        switch searchMode {
        case .flightNumber:
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return tripsWithoutFlight }
            return tripsWithoutFlight.filter {
                $0.origin.city.lowercased().contains(q)
                    || $0.destination.city.lowercased().contains(q)
                    || ($0.origin.iataCode?.lowercased().contains(q) ?? false)
                    || ($0.destination.iataCode?.lowercased().contains(q) ?? false)
            }
        case .route:
            guard let routeOrigin, let routeDestination else { return [] }
            return tripsWithoutFlight.filter { $0.origin.id == routeOrigin.id && $0.destination.id == routeDestination.id }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Add Flight")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Enter airline, airport, or flight")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    switch searchMode {
                    case .flightNumber:
                        TextField("Qantas, MEL, or QF123", text: $query)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    case .route:
                        VStack(spacing: Theme.Spacing.sm) {
                            CityMenuPicker(label: "From", selection: $routeOrigin)
                            CityMenuPicker(label: "To", selection: $routeDestination)
                        }
                    }

                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(SearchMode.allCases, id: \.self) { mode in
                            modeRow(mode)
                        }
                    }

                    if selectedTripID != nil {
                        flightNumberEntry
                    }

                    tripSuggestions
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                NavigationStack {
                    AddTripDetailsView(mode: .standalone, partnerName: appModel.partner.name) { _ in
                        showingAddTrip = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showingAddTrip = false }
                        }
                    }
                }
            }
        }
    }

    private func modeRow(_ mode: SearchMode) -> some View {
        Button {
            searchMode = mode
            selectedTripID = nil
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: mode.icon).foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 36, height: 36)
                Text(mode.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if searchMode == mode {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leafGreen)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tripSuggestions: some View {
        if tripsWithoutFlight.isEmpty {
            emptyStateHint
        } else if suggestedTrips.isEmpty {
            Text(searchMode == .route ? "No trip matches that route yet." : "No matching trips.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("TRIPS WITHOUT A FLIGHT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)
                ForEach(suggestedTrips) { trip in
                    Button {
                        selectedTripID = trip.id
                    } label: {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundStyle(Theme.skyBlue)
                            Text("\(trip.origin.iataCode ?? trip.origin.city) → \(trip.destination.iataCode ?? trip.destination.city)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text(trip.departureDate, format: .dateTime.day().month(.abbreviated))
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                            Image(systemName: selectedTripID == trip.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedTripID == trip.id ? Theme.leafGreen : Theme.subtleInk.opacity(0.3))
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var flightNumberEntry: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TextField("Flight number, e.g. QF35", text: $flightNumber)
                .textInputAutocapitalization(.characters)
                .padding()
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            Button(action: save) {
                if isSaving {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Save").font(.headline).frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)
            .disabled(flightNumber.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
        }
    }

    private var emptyStateHint: some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: "airplane.circle.fill").foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Every trip already has a flight").font(.headline)
                    Button("Add a new trip first") { showingAddTrip = true }
                        .font(.caption)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func save() {
        guard let selectedTripID else { return }
        isSaving = true
        Task {
            await appModel.addFlight(to: selectedTripID, flightNumber: flightNumber)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    AddFlightView()
        .environment(AppModel())
}
