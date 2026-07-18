//
//  MeasurementsSettingsView.swift
//  Twofold
//

import SwiftUI

struct MeasurementsSettingsView: View {
    @State private var system: MeasurementSystem = MeasurementPreference.current

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    // `.inline` renders as unreliable, unresponsive rows outside a real `List` —
                    // `SectionCard` is a plain VStack, so segmented (also a better fit for a
                    // binary choice) is what actually registers taps here.
                    Picker("Units", selection: $system) {
                        ForEach(MeasurementSystem.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Controls how distances are shown across Twofold — on this device only.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: system) { _, newValue in
            MeasurementPreference.current = newValue
        }
    }
}

#Preview {
    NavigationStack {
        MeasurementsSettingsView()
    }
}
