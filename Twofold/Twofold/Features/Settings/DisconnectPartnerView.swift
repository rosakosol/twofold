//
//  DisconnectPartnerView.swift
//  Twofold
//
//  Archived Data + Remove Partner — moved out of PartnerSetupView (which now only handles
//  editing your partner's name/photo/city) into its own screen under Help, since disconnecting
//  is a rare, consequential action that belongs behind a deliberate "I need help" navigation
//  path rather than sitting next to routine profile editing.
//

import PostHog
import SwiftUI

struct DisconnectPartnerView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingRemovePartnerConfirm = false
    @State private var isRemovingPartner = false
    @State private var removePartnerError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    NavigationLink {
                        ArchivedDataView()
                    } label: {
                        SettingsRow(title: "Archived Data", systemImage: "archivebox")
                    }
                    .buttonStyle(.plain)
                }

                SectionCard {
                    Button(role: .destructive) {
                        showingRemovePartnerConfirm = true
                    } label: {
                        HStack {
                            if isRemovingPartner {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Disconnect \(appModel.partner.name)").frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .disabled(isRemovingPartner)
                    Text("Archives everything you've shared, and lets you connect with someone new.")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                    if let removePartnerError {
                        Text(removePartnerError)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Disconnect Partner")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Remove \(appModel.partner.name)?", isPresented: $showingRemovePartnerConfirm) {
            Button("Remove Partner", role: .destructive) {
                Task {
                    isRemovingPartner = true
                    removePartnerError = nil
                    let failureReason = await appModel.removePartner()
                    isRemovingPartner = false
                    if let failureReason {
                        removePartnerError = failureReason
                    } else {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will archive all your shared trips, memories, flights, game sessions, stats, and drawings with \(appModel.partner.name) — they'll only be visible afterward in Settings' Archived Data. You'll be able to connect with someone new right away.")
        }
        .postHogScreenView("Settings: Disconnect Partner")
    }
}

#Preview {
    NavigationStack {
        DisconnectPartnerView()
            .environment(AppModel())
    }
}
