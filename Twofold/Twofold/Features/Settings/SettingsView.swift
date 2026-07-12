//
//  SettingsView.swift
//  Twofold
//
//  Reached from GlobeHomeView's toolbar. Owns the signed-in user's own profile editing
//  (name/photo/home city). For the partner: their photo and name are always personal and
//  always editable (your own custom pick/nickname, independent of what they've set for
//  themselves or for you) — but their home city is only a guess you can set before real
//  pairing happens, since it's shared/real data once paired. Also owns the couple's
//  anniversary date, subscription management, and sign-out.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var homeCity: Place?
    @State private var partnerName: String = ""
    @State private var partnerCity: Place?
    @State private var anniversaryDate: Date = .now
    @State private var isSaving = false
    @State private var avatarError: String?
    @State private var partnerAvatarError: String?
    @State private var showingPaywall = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false
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
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageURL: appModel.currentUser.avatarURL, size: 96) { data in
                        Task {
                            do {
                                try await appModel.updateAvatar(imageData: data)
                                avatarError = nil
                            } catch {
                                avatarError = error.localizedDescription
                            }
                        }
                    }
                    .padding(.top, Theme.Spacing.md)

                    if let avatarError {
                        Text(avatarError)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }

                    SectionCard {
                        Text("Your profile").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        TextField("Name", text: $name)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        CityMenuPicker(label: "Home city", selection: $homeCity)
                    }

                    partnerCard

                    if !appModel.partnerConnected {
                        partnerConnectionCard
                    }

                    SectionCard {
                        Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        DatePicker("Together since", selection: $anniversaryDate, in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    SectionCard {
                        Button {
                            showingPaywall = true
                        } label: {
                            HStack {
                                Label("Manage subscription", systemImage: "star.fill")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    SectionCard {
                        NavigationLink {
                            NotificationPreferencesView()
                        } label: {
                            HStack {
                                Label("Notifications", systemImage: "bell.fill")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    SectionCard {
                        NavigationLink {
                            ArchivedDataView()
                        } label: {
                            HStack {
                                Label("Archived Data", systemImage: "archivebox")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if appModel.partnerConnected {
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

                    SectionCard {
                        Button(role: .destructive) {
                            showingSignOutConfirm = true
                        } label: {
                            HStack {
                                if isSigningOut {
                                    ProgressView().frame(maxWidth: .infinity)
                                } else {
                                    Text("Sign Out").frame(maxWidth: .infinity)
                                }
                            }
                        }
                        .disabled(isSigningOut)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Task {
                            isSaving = true
                            await appModel.updateProfile(name: name, homeCity: homeCity)
                            // The nickname is always personal, paired or not — but the city is
                            // only ever a guess pre-pairing (shared/real once paired, and
                            // SettingsView doesn't even show an editable field for it then).
                            await appModel.updatePartnerName(partnerName)
                            if !appModel.partnerConnected, let partnerCity {
                                await appModel.updatePartnerHomeCity(partnerCity)
                            }
                            await appModel.updateAnniversaryDate(anniversaryDate)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                name = appModel.currentUser.name
                homeCity = appModel.currentUser.homeCity
                partnerName = appModel.partner.name
                partnerCity = appModel.partner.homeCity
                anniversaryDate = appModel.couple.startedDatingOn
            }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack { PaywallView() }
            }
            .confirmationDialog("Sign out of Twofold?", isPresented: $showingSignOutConfirm, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task {
                        isSigningOut = true
                        await appModel.signOut()
                    }
                }
                Button("Cancel", role: .cancel) {}
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
                Text("This will archive all your shared trips, memories, flights, game sessions, stats, and doodles with \(appModel.partner.name) — they'll only be visible afterward in Settings' Archived Data. You'll be able to connect with someone new right away.")
            }
        }
    }

    private var partnerCard: some View {
        SectionCard {
            Text("Partner")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

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
            .frame(maxWidth: .infinity)

            if let partnerAvatarError {
                Text(partnerAvatarError)
                    .font(.caption)
                    .foregroundStyle(Theme.heartRed)
                    .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                TextField("Their name", text: $partnerName)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .padding()
                    .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                // A nickname is always personal — your partner has their own independent name
                // for you, and neither side ever overwrites the other's.
                Text("Just for you — they won't see this name.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }

            if appModel.partnerConnected {
                // Unlike the name, home city is shared/real once paired — not a personal guess.
                HStack {
                    Text("City").foregroundStyle(Theme.subtleInk)
                    Spacer()
                    Text(appModel.partner.homeCity?.city ?? "—").foregroundStyle(Theme.ink)
                }
                .padding()
                .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            } else {
                CityMenuPicker(label: "Their city", selection: $partnerCity)
            }
        }
    }

    /// Either direction of pairing, reachable permanently (not just during onboarding) — closes
    /// the gap where someone who already made their own account had no way to link up with a
    /// partner who invited them, or to send their own invite after the fact.
    private var partnerConnectionCard: some View {
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
            }
            .buttonStyle(.plain)
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
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
