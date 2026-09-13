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

                    // Ungated and partner-only, unlike the Relationship Record on the main
                    // Settings screen. That one is a keepsake and can be a Premium perk; this is
                    // the complete copy, and a portability request does not care what anyone is
                    // paying. It sits here rather than out front for the same reason Delete
                    // Account does: rarely needed, and wanted at the moment someone is looking for
                    // help rather than browsing settings.
                    if appModel.partnerConnected {
                        Divider()

                        NavigationLink {
                            ExportDataView()
                        } label: {
                            SettingsRow(title: "Export your data", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.plain)
                    }

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

                    Divider()

                    // Moved here from the main Settings screen's own destructive-actions card —
                    // deleting your account is a support-adjacent, rarely-needed action, not
                    // something that should sit as prominently as Sign Out.
                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        SettingsRow(title: "Delete Account", systemImage: "trash.fill", isDestructive: true)
                    }
                    .buttonStyle(.plain)
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
