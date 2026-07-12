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
    @State private var homeCity: Place?
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
                    CityMenuPicker(label: "Home city", selection: $homeCity)

                    Button {
                        locationService.requestCurrentLocation()
                    } label: {
                        HStack {
                            if locationService.state == .requesting {
                                ProgressView()
                                Text("Finding your city…").foregroundStyle(Theme.subtleInk)
                            } else {
                                Label("Use my current location", systemImage: "location.fill")
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
                homeCity = place
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
            homeCity = appModel.currentUser.homeCity
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updateProfile(name: name, homeCity: homeCity)
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
