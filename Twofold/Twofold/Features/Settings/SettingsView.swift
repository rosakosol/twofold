//
//  SettingsView.swift
//  Twofold
//
//  Reached from GlobeHomeView's toolbar. Owns the signed-in user's own profile editing
//  (name/photo/home city — never the partner's, matching the RLS-enforced "own row only"
//  rule already used throughout BackendService) plus subscription management and sign-out.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var homeCity: Place?
    @State private var isSaving = false
    @State private var showingPaywall = false
    @State private var showingSignOutConfirm = false
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", size: 96) { data in
                        Task { await appModel.updateAvatar(imageData: data) }
                    }
                    .padding(.top, Theme.Spacing.md)

                    SectionCard {
                        Text("Your profile").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        TextField("Name", text: $name)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .padding()
                            .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        CityMenuPicker(label: "Home city", selection: $homeCity)
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
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
