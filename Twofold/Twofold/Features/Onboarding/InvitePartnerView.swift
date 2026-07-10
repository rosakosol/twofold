//
//  InvitePartnerView.swift
//  Twofold
//
//  Real invite flow — unlike the sell screens around it, this one actually talks to the
//  backend. Only reachable once SaveAccountView has run, since generating a real, redeemable
//  code requires a signed-in account. Combines "send my code" and "enter their code" on one
//  screen (unlike the preserved deep-link path's ConnectPartnerView/ShareInviteView, which
//  splits those into separate screens) to match the reference flow this was modeled on.
//
//  If the user redeems a partner's code here (rather than sending their own), a real couple
//  now exists — `applyOnboardingAccount` picks that up and flips `hasCouple`, which `RootView`
//  uses to jump straight into `MainTabView`, skipping the remaining onboarding screens. That's
//  correct: they've just joined an already-set-up couple, whose subscription already covers
//  them (Twofold subscriptions are shared), so there's nothing left for them to set up.
//

import SwiftUI

struct InvitePartnerView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    @State private var isCreatingCode = false
    @State private var createError: String?

    @State private var partnerCodeInput = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var didCopy = false

    private var shareURL: URL? {
        onboarding.inviteCode.map { InviteCode.shareURL(for: $0) }
    }

    var body: some View {
        OnboardingScaffold(
            title: "Connect with \(onboarding.partnerName) ❤️",
            subtitle: "Send them your code, or enter theirs to connect right now.",
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    sendCodeCard
                    enterCodeCard
                }
            },
            primaryTitle: nil,
            primaryAction: nil,
            secondaryTitle: "Not now",
            secondaryAction: { onboarding.path.append(.addFirstFlight) }
        )
        .onAppear {
            if onboarding.inviteCode == nil {
                createCode()
            }
        }
    }

    private var sendCodeCard: some View {
        SectionCard {
            Text("Send this code to \(onboarding.partnerName)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            if let code = onboarding.inviteCode {
                Text(code)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.skyBlue)
                    .frame(maxWidth: .infinity, alignment: .center)

                if let shareURL {
                    HStack(spacing: Theme.Spacing.sm) {
                        ShareLink(item: shareURL) {
                            Label("Send code", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .background(Theme.skyBlue, in: Capsule())
                        .foregroundStyle(.white)

                        Button {
                            UIPasteboard.general.string = shareURL.absoluteString
                            didCopy = true
                        } label: {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .background(Theme.backgroundGradient.opacity(0.6), in: Circle())
                        .foregroundStyle(Theme.ink)
                    }
                }
            } else if isCreatingCode {
                ProgressView().frame(maxWidth: .infinity)
            } else if let createError {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(createError)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                    Button("Try again", action: createCode)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.skyBlue)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var enterCodeCard: some View {
        SectionCard {
            Text("Enter \(onboarding.partnerName)'s code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            TextField("Enter the code", text: $partnerCodeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(Theme.backgroundGradient.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            if let redeemError {
                Text(redeemError)
                    .font(.caption)
                    .foregroundStyle(Theme.heartRed)
            }

            Button {
                redeemCode()
            } label: {
                if isRedeeming {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Connect").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(
                partnerCodeInput.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming
                    ? Theme.subtleInk.opacity(0.3) : Theme.skyBlue,
                in: Capsule()
            )
            .foregroundStyle(.white)
            .disabled(partnerCodeInput.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)
        }
    }

    private func createCode() {
        isCreatingCode = true
        createError = nil
        Task {
            do {
                onboarding.inviteCode = try await BackendService.createInviteCode(firstName: onboarding.firstName)
            } catch {
                createError = error.localizedDescription
            }
            isCreatingCode = false
        }
    }

    private func redeemCode() {
        isRedeeming = true
        redeemError = nil
        Task {
            do {
                try await BackendService.redeemInviteCode(partnerCodeInput.trimmingCharacters(in: .whitespaces))
                // Picks up the couple that redeeming just created — if found, this sets
                // `appModel.hasCouple = true`, and `RootView` takes it from here.
                await appModel.applyOnboardingAccount(onboarding)
                if !appModel.hasCouple {
                    onboarding.path.append(.addFirstFlight)
                }
            } catch {
                redeemError = error.localizedDescription
            }
            isRedeeming = false
        }
    }
}

#Preview {
    NavigationStack {
        InvitePartnerView()
    }
    .environment({
        let model = OnboardingModel()
        model.partnerName = "Erin"
        model.firstName = "Rosa"
        return model
    }())
    .environment(AppModel())
}
