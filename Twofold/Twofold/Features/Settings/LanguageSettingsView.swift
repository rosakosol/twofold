//
//  LanguageSettingsView.swift
//  Twofold
//
//  Twofold is English-only today — no in-app translation infrastructure exists yet. Rather than
//  a fake picker with one disabled option, this deep-links to the system Settings app's own
//  per-app language page (iOS handles that natively once any localization exists; until then
//  it's still the honest, standard place to point someone who goes looking).
//

import PostHog
import SwiftUI

struct LanguageSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    HStack {
                        Text("Current language").foregroundStyle(Theme.subtleInk)
                        Spacer()
                        Text(Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? "English")
                            .foregroundStyle(Theme.ink)
                    }
                }

                SectionCard {
                    Text("More languages are coming soon.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Twofold is currently available in English only.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(title: "Open iOS Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Language")
    }
}

#Preview {
    NavigationStack {
        LanguageSettingsView()
    }
}
