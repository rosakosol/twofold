//
//  PartnerSetupView.swift
//  Twofold
//
//  Opened from Home's "Set up your partner" card whenever there's no connected partner (fresh
//  account, or after removing one) — a focused screen combining what was previously spread
//  across Settings' partner card (name/photo/city) and anniversary section, plus the actual
//  connect step, so getting a partner set up doesn't require bouncing between Home's checklist
//  and Settings.
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

                    SectionCard {
                        Text("Their city").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        CityMenuPicker(label: "Their city", selection: $partnerCity)
                    }

                    SectionCard {
                        Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        DatePicker("Together since", selection: $anniversaryDate, in: ...Date.now, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    connectCard
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
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updatePartnerName(partnerName)
            if let partnerCity {
                await appModel.updatePartnerHomeCity(partnerCity)
            }
            await appModel.updateAnniversaryDate(anniversaryDate)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    PartnerSetupView()
        .environment(AppModel())
}
