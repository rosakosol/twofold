//
//  FlightNumberStepView.swift
//  Twofold
//

import SwiftUI
import PostHog

struct FlightNumberStepView: View {
    @Environment(AddFlightFlowModel.self) private var model

    var body: some View {
        @Bindable var model = model

        AddFlightStepScaffold(subtitle: "Enter flight number") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        model.path.append(.airlinePicker)
                    } label: {
                        Text(model.airlineEntry?.iata ?? "QF")
                            .font(.headline)
                            .foregroundStyle(model.airlineEntry == nil ? Theme.subtleInk.opacity(0.5) : Theme.ink)
                            .frame(minWidth: 56)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    TextField("123", text: $model.flightNumberDigits)
                        .keyboardType(.numberPad)
                        .font(.title3)
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }

                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: "number")
                        .foregroundStyle(Theme.subtleInk)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tip: Just The Numbers").font(.subheadline.weight(.semibold))
                        Text("Not including airline code").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                }

                if let airline = model.airlineEntry, !model.flightNumberDigits.isEmpty {
                    Button {
                        model.path.append(.date)
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            AirlineLogoView(url: AirlineLogo.url(forIATACode: airline.iata), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(airline.name) \(model.flightNumberDigits)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Detected flight number")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleInk)
                            }
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
        }
        .postHogScreenView("Flights: Add Flight — Flight Number")
    }
}
