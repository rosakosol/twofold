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

    var mode: Mode
    var partnerName: String = "Partner"
    var onSave: (Trip) -> Void = { _ in }

    @Environment(AppModel.self) private var appModel
    @State private var origin: Place?
    @State private var destination: Place?
    @State private var departureDate = Date().addingTimeInterval(86_400 * 30)
    @State private var returnDate = Date().addingTimeInterval(86_400 * 44)
    @State private var traveler: TripTraveler = .you
    @State private var wantsFlight = false
    @State private var flightNumber = ""

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
                        DatePicker("Departing", selection: $departureDate, displayedComponents: .date)
                        DatePicker("Returning", selection: $returnDate, in: departureDate..., displayedComponents: .date)
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
            primaryDisabled: origin == nil || destination == nil
        )
    }

    private func save() {
        guard let origin, let destination else { return }
        let trip = appModel.addTrip(
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: returnDate,
            traveler: traveler,
            flightNumber: wantsFlight ? flightNumber : nil
        )
        onSave(trip)
    }
}

#Preview {
    NavigationStack {
        AddTripDetailsView(mode: .onboarding)
    }
    .environment(AppModel())
}
