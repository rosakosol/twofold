//
//  AddTripDetailsView.swift
//  Twofold
//
//  Shared by the onboarding "add our next trip" step and the home screen's
//  progressive "Add your next trip" checklist card — the caller decides what
//  happens after saving via `onSave`.
//

import SwiftUI

struct AddTripDetailsView: View {
    enum Mode {
        case onboarding
        case standalone
    }

    /// Seeds initial field values — used by the flight-email review flow to prefill
    /// whatever the parser confidently extracted, leaving the rest for manual entry.
    struct Prefill {
        var origin: Place?
        var destination: Place?
        var departureDate: Date?
        var returnDate: Date?
        var flightNumber: String?
    }

    var mode: Mode
    var partnerName: String = "Partner"
    var onSave: (Trip) -> Void = { _ in }

    @Environment(AppModel.self) private var appModel
    @State private var origin: Place?
    @State private var destination: Place?
    @State private var departureDate: Date
    @State private var returnDate: Date
    @State private var traveler: TripTraveler = .you
    @State private var category: TripCategory = .seeingEachOther
    @State private var flightNumberHint: String
    @State private var selectedFlightCandidate: AeroFlightCandidate?
    @State private var showingAddFlightFlow = false
    @State private var isSaving = false

    init(mode: Mode, partnerName: String = "Partner", prefill: Prefill? = nil, onSave: @escaping (Trip) -> Void = { _ in }) {
        self.mode = mode
        self.partnerName = partnerName
        self.onSave = onSave
        _origin = State(initialValue: prefill?.origin)
        _destination = State(initialValue: prefill?.destination)
        _departureDate = State(initialValue: prefill?.departureDate ?? Date().addingTimeInterval(86_400 * 30))
        _returnDate = State(initialValue: prefill?.returnDate ?? prefill?.departureDate?.addingTimeInterval(86_400 * 14) ?? Date().addingTimeInterval(86_400 * 44))
        _flightNumberHint = State(initialValue: prefill?.flightNumber ?? "")
    }

    var body: some View {
        OnboardingScaffold(
            title: "Where are you going?",
            subtitle: mode == .onboarding ? "This is a natural first step — you can always add more trips later." : nil,
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    CityMenuPicker(label: "From", selection: $origin)
                    CityMenuPicker(label: "To", selection: $destination)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("When?").font(.caption).foregroundStyle(Theme.subtleInk)
                        DatePicker("Departing", selection: $departureDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Returning", selection: $returnDate, in: departureDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Who's travelling?").font(.caption).foregroundStyle(Theme.subtleInk)
                        Picker("Who's travelling?", selection: $traveler) {
                            Text("You").tag(TripTraveler.you)
                            Text(partnerName).tag(TripTraveler.partner)
                            Text("Both").tag(TripTraveler.both)
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Reason for travel").font(.caption).foregroundStyle(Theme.subtleInk)
                        Picker("Reason for travel", selection: $category) {
                            ForEach(TripCategory.allCases, id: \.self) { option in
                                Text(option.shortLabel).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    addFlightRow
                }
            },
            primaryTitle: "Save trip",
            primaryAction: save,
            primaryDisabled: origin == nil || destination == nil || isSaving
        )
        .sheet(isPresented: $showingAddFlightFlow) {
            AddFlightFlowView(
                nearCoordinate: origin?.coordinate,
                initialFlightNumberDigits: flightNumberHint.isEmpty ? nil : flightNumberHint,
                topBarTitle: "Cancel",
                onTopBarAction: { showingAddFlightFlow = false },
                completion: .handOff { candidate in
                    selectedFlightCandidate = candidate
                    showingAddFlightFlow = false
                }
            )
        }
    }

    /// Tapping through opens the real AeroAPI-backed AddFlightFlowView search (the same wizard
    /// used elsewhere in the app) — flights are never self-reported, so a flight only ever
    /// attaches to this trip once a real candidate comes back from that search. When this view
    /// was opened from the forwarded-flight-email review flow, whatever number the parser
    /// picked out of the email is shown as a hint and pre-fills the search rather than being
    /// saved as-is.
    private var addFlightRow: some View {
        Button {
            showingAddFlightFlow = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let candidate = selectedFlightCandidate {
                    AirlineLogoView(url: candidate.logoURL, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayFlightNumber)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let originCity = candidate.origin?.city, let destinationCity = candidate.destination?.city {
                            Text("\(originCity) to \(destinationCity)")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        selectedFlightCandidate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.subtleInk)
                    }
                } else {
                    Image(systemName: "airplane")
                        .foregroundStyle(Theme.skyBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flightNumberHint.isEmpty ? "Add a flight" : flightNumberHint)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        if !flightNumberHint.isEmpty {
                            Text("From your forwarded email — tap to find and confirm")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let origin, let destination else { return }
        isSaving = true
        Task {
            let trip = await appModel.addTrip(
                origin: origin,
                destination: destination,
                departureDate: departureDate,
                arrivalDate: returnDate,
                traveler: traveler,
                category: category
            )
            if let selectedFlightCandidate {
                // Real AeroAPI-tracked flight only — no self-reported fallback. Can fail if
                // there's no active couple yet; the trip is still saved either way.
                _ = try? await AeroFlightService.addFlight(faFlightId: selectedFlightCandidate.faFlightId, tripID: trip.id, notifyMe: true)
                await appModel.refreshFlights()
            }
            isSaving = false
            onSave(trip)
        }
    }
}

#Preview {
    NavigationStack {
        AddTripDetailsView(mode: .onboarding)
    }
    .environment(AppModel())
}
