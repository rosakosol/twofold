//
//  AddFlightEntryStepView.swift
//  Twofold
//
//  Root of the AddFlightFlowView wizard. The central text field is dual-purpose: typing digits
//  routes into the flight-number path, typing letters routes into the airport-search path —
//  plus explicit "Find by Flight Number"/"Find by Route" rows for anyone who taps without
//  typing first.
//

import SwiftUI

struct AddFlightEntryStepView: View {
    @Environment(AddFlightFlowModel.self) private var model
    @State private var query = ""

    var body: some View {
        AddFlightStepScaffold(subtitle: "Search by flight number or route") {
            VStack(spacing: Theme.Spacing.md) {
                TextField("Flight number or airport", text: $query)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .onSubmit(routeFromQuery)

                VStack(spacing: Theme.Spacing.sm) {
                    modeRow(icon: "number", title: "Find by Flight Number") {
                        model.mode = .flightNumber
                        model.flightNumberDigits = digitsOnly(query)
                        model.path.append(.flightNumber)
                    }
                    modeRow(icon: "arrow.triangle.swap", title: "Find by Route") {
                        model.mode = .route
                        model.path.append(.airport(.departure))
                    }
                }
            }
        }
    }

    private func digitsOnly(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    private func routeFromQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if trimmed.first?.isNumber == true {
            model.mode = .flightNumber
            model.flightNumberDigits = digitsOnly(trimmed)
            model.path.append(.flightNumber)
        } else {
            model.mode = .route
            model.path.append(.airport(.departure))
        }
    }

    private func modeRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: icon).foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 36, height: 36)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
