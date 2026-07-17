//
//  PartnerSetupView.swift
//  Twofold
//
//  Every partner-relationship-scoped screen in one place — reachable both pre-connection
//  (Home's "Set up your partner" card, and Settings' "Connect with your partner" row) and
//  post-connection (Settings' "About your partner" row, same destination, different label).
//  Pre-connection it's name/photo/city/anniversary plus the connect step, so first-time setup
//  doesn't require bouncing between screens. Once connected, anniversary editing moves solely to
//  AboutRelationshipView (couple-level, not partner-specific) and this screen instead surfaces
//  Archived Data and Remove Partner — both are about *this* partner relationship, same as
//  everything else here.
//

import SwiftUI

struct PartnerSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var partnerName: String = ""
    @State private var partnerCity: Place?
    @State private var anniversaryDate: Date = .now
    @State private var partnerAvatarError: String?
    @State private var isSaving = false
    @State private var showingShareInvite = false
    @State private var showingRedeemCode = false
    @State private var isCreatingInvite = false
    @State private var showingRemovePartnerConfirm = false
    @State private var isRemovingPartner = false
    @State private var removePartnerError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageURL: appModel.partner.avatarURL, size: 96) { data in
                        Task {
                            do {
                                try await appModel.updatePartnerAvatar(imageData: data)
                                partnerAvatarError = nil
                            } catch {
                                partnerAvatarError = error.localizedDescription
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.md)

                    if let partnerAvatarError {
                        Text(partnerAvatarError)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }

                    SectionCard {
                        Text("Their name").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        TextField("Their name", text: $partnerName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        // A nickname is always personal — your partner has their own
                        // independent name for you, and neither side ever overwrites the
                        // other's.
                        Text("Just for you — they won't see this name.")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }

                    if appModel.partnerConnected {
                        SectionCard {
                            HStack {
                                Text("City").foregroundStyle(Theme.subtleInk)
                                Spacer()
                                Text(appModel.partner.homeCity?.displayCity ?? "—").foregroundStyle(Theme.ink)
                            }
                        }
                    } else {
                        SectionCard {
                            Text("Their city").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                            CityMenuPicker(label: "Their city", selection: $partnerCity)
                        }
                    }

                    if !appModel.partnerConnected {
                        SectionCard {
                            Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                            DatePicker("Together since", selection: $anniversaryDate, in: ...Date.now, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        }
                    }

                    if !appModel.partnerConnected {
                        connectCard
                    } else {
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
                                        Text("Remove Partner").frame(maxWidth: .infinity)
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
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Your Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                // "Partner" is the unpaired placeholder name — an empty field reads better
                // than prefilling that literal word as if it were a saved nickname.
                partnerName = appModel.partner.name == "Partner" ? "" : appModel.partner.name
                partnerCity = appModel.partner.homeCity
                anniversaryDate = appModel.couple.startedDatingOn
            }
            .sheet(isPresented: $showingShareInvite) {
                NavigationStack {
                    ShareInviteView(code: appModel.inviteCode ?? "") {
                        showingShareInvite = false
                    }
                }
            }
            .sheet(isPresented: $showingRedeemCode) {
                RedeemPartnerCodeView()
            }
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
        }
    }

    private var connectCard: some View {
        SectionCard {
            Text("Connect with your partner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            Button {
                Task {
                    isCreatingInvite = true
                    if appModel.inviteCode == nil {
                        appModel.inviteCode = try? await BackendService.createInviteCode(firstName: appModel.currentUser.name)
                    }
                    isCreatingInvite = false
                    if appModel.inviteCode != nil { showingShareInvite = true }
                }
            } label: {
                HStack {
                    if isCreatingInvite {
                        ProgressView()
                    } else {
                        Label("Share my invite code", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCreatingInvite)

            Button {
                showingRedeemCode = true
            } label: {
                HStack {
                    Label("Enter their code", systemImage: "person.fill.checkmark")
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updatePartnerName(partnerName)
            // City and anniversary are only editable here pre-connection — once paired, city is
            // real shared data (not a guess) and anniversary editing lives solely in
            // AboutRelationshipView, so saving them here post-connection would just be
            // re-writing an unchanged value from a field that isn't even shown.
            if !appModel.partnerConnected {
                if let partnerCity {
                    await appModel.updatePartnerHomeCity(partnerCity)
                }
                await appModel.updateAnniversaryDate(anniversaryDate)
            }
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    PartnerSetupView()
        .environment(AppModel())
}
