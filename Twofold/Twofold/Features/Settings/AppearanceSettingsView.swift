//
//  AppearanceSettingsView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct AppearanceSettingsView: View {
    /// Bound straight to the shared store rather than mirrored into `@State` and written back on
    /// change — one source of truth, so the control can't drift from what the rest of the app is
    /// rendering. Same shape as `MeasurementsSettingsView`.
    @Bindable private var store = AppearancePreferenceStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    // `.inline` renders as unreliable, unresponsive rows outside a real `List` —
                    // `SectionCard` is a plain VStack, so segmented (also a better fit for a
                    // 3-way choice) is what actually registers taps here.
                    Picker("Appearance", selection: $store.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Text("Controls whether Twofold uses Light or Dark appearance, or follows your device's system setting — on this device only.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Appearance")
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
}
