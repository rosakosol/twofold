//
//  AboutYouView.swift
//  Twofold
//
//  Your own profile — avatar, name, home city. Split out of the old monolithic SettingsView
//  as part of the Settings/Profile IA restructure.
//

import SwiftUI

struct AboutYouView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var avatarError: String?
    @State private var isSaving = false
    @State private var locationService = HomeLocationService()

    var body: some View {
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

                    // Current city is location-derived automatically (see RootView's foreground
                    // refresh) — no manual picker here anymore, just a status readout and a way
                    // to force an immediate re-check right after actually landing somewhere new,
                    // rather than waiting for the next natural foreground trigger.
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current city").font(.caption).foregroundStyle(Theme.subtleInk)
                            Text(appModel.currentUser.homeCity.map { "\($0.displayCity), \($0.country)" } ?? "Not detected yet")
                                .foregroundStyle(Theme.ink)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    Button {
                        locationService.requestCurrentLocation()
                    } label: {
                        HStack {
                            if locationService.state == .requesting {
                                ProgressView()
                                Text("Checking…").foregroundStyle(Theme.subtleInk)
                            } else {
                                Label("Refresh current city", systemImage: "location.fill")
                                    .foregroundStyle(Theme.skyBlue)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(locationService.state == .requesting)

                    switch locationService.state {
                    case .deniedOrRestricted:
                        Text("Location access is off. Enable it in Location Permission settings to use this.")
                            .font(.caption2)
                            .foregroundStyle(Theme.heartRed)
                    case .failed(let message):
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(Theme.heartRed)
                    default:
                        EmptyView()
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .onChange(of: locationService.state) { _, newState in
            if case .resolved(let place) = newState {
                Task { await appModel.updateCurrentCityIfChanged(place) }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("About You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
            name = appModel.currentUser.name
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updateProfile(name: name)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        AboutYouView()
    }
    .environment(AppModel())
}
