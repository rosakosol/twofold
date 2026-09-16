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

                    // Ungated, and the only route to this screen.
                    //
                    // It used to live inside "Disconnect my partner" below, which is gated on
                    // `partnerConnected` — so it disappeared at exactly the moment it started
                    // mattering. The subscription-ended card, Delete Account and both published
                    // documents all tell somebody whose partner has just left to come here and
                    // export before the archive's 90 days run out, and for that person there was
                    // no way in.
                    //
                    // Shown even with no archives: `ArchivedDataView` has its own "No archived
                    // data" state, and a row that is sometimes missing is how this went wrong.
                    Divider()

                    NavigationLink {
                        ArchivedDataView()
                    } label: {
                        SettingsRow(title: "Archived Data", systemImage: "archivebox")
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
