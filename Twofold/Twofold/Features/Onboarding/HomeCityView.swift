//
//  HomeCityView.swift
//  Twofold
//

import SwiftUI

struct HomeCityView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var selected: Place?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var locationService = HomeLocationService()

    var body: some View {
        OnboardingScaffold(
            title: "Where are you based?",
            subtitle: "We'll use this to show the distance between you two.",
            content: {
                VStack(spacing: Theme.Spacing.sm) {
                    CityMenuPicker(label: "Your city", selection: $selected)

                    Button {
                        locationService.requestCurrentLocation()
                    } label: {
                        HStack {
                            if locationService.state == .requesting {
                                ProgressView()
                                Text("Finding your city…").foregroundStyle(Theme.subtleInk)
                            } else {
                                Label("Use my current location", systemImage: "location.fill")
                                    .foregroundStyle(Theme.skyBlueText)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(locationService.state == .requesting)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRedText)
                    }
                    if case .deniedOrRestricted = locationService.state {
                        Text("Location access is off — you can still search for your city above.")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .onChange(of: locationService.state) { _, newState in
                    if case .resolved(let place) = newState {
                        selected = place
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { advance() },
            // Same as `AddPhotoView`: the skip button called `advance()` as well. `advance` saves
            // a city only `if let selected`, so Continue with nothing chosen has always been the
            // skip — there was never a second behaviour for the second button to reach.
            primaryDisabled: isSaving
        )
        .onAppear {
            if selected == nil {
                locationService.requestCurrentLocation()
            }
        }
    }

    private func advance() {
        onboarding.homeCity = selected
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let selected {
                    try await BackendService.updateHomeCity(selected)
                    appModel.couple.partnerA.homeCity = selected
                }
                if onboarding.role == .invitee, let code = onboarding.inviteCode {
                    // Looked up before redeeming — the code has to still be genuinely pending
                    // for this to resolve, which it no longer is the instant redeem succeeds.
                    // Populates `onboarding.inviterName`/`inviterAvatarURL` for
                    // AddPhotoView/ConnectionRequestSentView just ahead — real values, not a
                    // guess, since codes carry no name/avatar information at all now.
                    if let info = try? await BackendService.inviterInfo(forCode: code) {
                        onboarding.inviterName = info.name
                        onboarding.inviterAvatarURL = info.avatarURL
                    }
                    // Carried on the model rather than assumed here. This used to hardcode
                    // `.link`, on the strength of a comment claiming only a tapped link could
                    // reach it — but `EnterPartnerCodeView` appends `.joinInvite` for anyone
                    // typing a code before they have an account, and that lands here too. So
                    // signing up fresh with a typed code paired immediately, with no approval,
                    // which is the whole distinction the two origins exist to draw.
                    let outcome = try await BackendService.redeemInviteCode(code, origin: onboarding.inviteOrigin)
                    onboarding.connectedOnRedeem = outcome.connected
                }
                onboarding.path.append(.addPhoto)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        HomeCityView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
