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
    @State private var wantsFlight: Bool
    @State private var flightNumber: String
    @State private var isSaving = false

    init(mode: Mode, partnerName: String = "Partner", prefill: Prefill? = nil, onSave: @escaping (Trip) -> Void = { _ in }) {
        self.mode = mode
        self.partnerName = partnerName
        self.onSave = onSave
        _origin = State(initialValue: prefill?.origin)
        _destination = State(initialValue: prefill?.destination)
        _departureDate = State(initialValue: prefill?.departureDate ?? Date().addingTimeInterval(86_400 * 30))
        _returnDate = State(initialValue: prefill?.returnDate ?? prefill?.departureDate?.addingTimeInterval(86_400 * 14) ?? Date().addingTimeInterval(86_400 * 44))
        _wantsFlight = State(initialValue: prefill?.flightNumber != nil)
        _flightNumber = State(initialValue: prefill?.flightNumber ?? "")
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

                    VStack(spacing: Theme.Spacing.sm) {
                        Toggle("Add a flight", isOn: $wantsFlight)
                        if wantsFlight {
                            TextField("Flight number, e.g. QF35", text: $flightNumber)
                                .textInputAutocapitalization(.characters)
                                .padding()
                                .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
            },
            primaryTitle: "Save trip",
            primaryAction: save,
            primaryDisabled: origin == nil || destination == nil || isSaving
        )
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
                category: category,
                flightNumber: wantsFlight ? flightNumber : nil
            )
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
