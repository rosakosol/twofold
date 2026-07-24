//
//  HelpView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct HelpView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    // Support is the single entry point for getting in touch — feedback is a
                    // category inside its form now, not its own screen.
                    NavigationLink {
                        SupportView()
                    } label: {
                        SettingsRow(title: "Support", systemImage: "questionmark.circle.fill")
                    }
                    .buttonStyle(.plain)

                    // Only meaningful once there's an actual partner to disconnect from —
                    // reachable pre-connection otherwise makes no sense.
                    if appModel.partnerConnected {
                        Divider()

                        NavigationLink {
                            DisconnectPartnerView()
                        } label: {
                            SettingsRow(title: "Disconnect my partner", systemImage: "person.fill.xmark")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Help")
    }
}

#Preview {
    NavigationStack {
        HelpView()
            .environment(AppModel())
    }
}
