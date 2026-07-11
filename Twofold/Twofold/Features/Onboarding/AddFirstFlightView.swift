//
//  AddFirstFlightView.swift
//  Twofold
//
//  There's no real flight-schedule lookup API in this app (only forwarded-email parsing,
//  a different feature), so "Find flight" can't independently verify a flight the way a
//  real search would — it saves exactly what's entered rather than fabricating a result.
//  A date is collected alongside the number since the schema requires one and nothing can
//  infer it. Defaults to the reunion direction: partner's city → your city.
//

import SwiftUI

struct AddFirstFlightView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var flightNumber = ""
    @State private var date = Date().addingTimeInterval(86_400 * 14)
    @State private var isSaving = false

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    var body: some View {
        OnboardingScaffold(
            title: "Let's track your first flight ✈️",
            subtitle: "Add a flight for you or \(partnerName)",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    TextField("Flight number, e.g. QF9", text: $flightNumber)
                        .textInputAutocapitalization(.characters)
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    DatePicker("Departure", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
            },
            primaryTitle: "Find flight",
            primaryAction: save,
            primaryDisabled: flightNumber.trimmingCharacters(in: .whitespaces).isEmpty || isSaving,
            secondaryTitle: "Add this later",
            secondaryAction: { onboarding.path.append(.firstMemory) }
        )
    }

    private func save() {
        onboarding.draftedFlightNumber = flightNumber.trimmingCharacters(in: .whitespaces)
        onboarding.draftedFlightDate = date

        guard let origin = onboarding.partnerCity, let destination = onboarding.homeCity else {
            onboarding.path.append(.firstMemory)
            return
        }

        isSaving = true
        Task {
            await appModel.addTrip(
                origin: origin,
                destination: destination,
                departureDate: date,
                arrivalDate: date.addingTimeInterval(3600 * 4),
                traveler: .partner,
                category: .seeingEachOther,
                flightNumber: onboarding.draftedFlightNumber
            )
            isSaving = false
            onboarding.path.append(.twofoldPreview)
        }
    }
}

#Preview {
    NavigationStack {
        AddFirstFlightView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
