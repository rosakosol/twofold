//
//  SaveAccountView.swift
//  Twofold
//
//  Sits right after the feature "sell" screens, before the real partner-invite screen — the
//  user's already seen the value (notifications, Live Activities, memories, widgets) before
//  hitting this friction, and a real account needs to exist before a real invite code can be
//  generated. Everything collected so far (situation, frequency, attribution, goals, names,
//  cities, photos, anniversary date) has been sitting in `OnboardingModel` only — nothing
//  persists until this succeeds, at which point `AppModel.applyOnboardingAccount` applies all
//  of it in one shot. `RootView` doesn't swap to `MainTabView` yet, though — that only happens
//  once `AppModel.finishOnboarding()` runs, after the invite/paywall/trial screens that follow.
//

import SwiftUI

struct SaveAccountView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var showingEmailForm = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var canContinueWithEmail: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && password.count >= 6 && confirmPassword == password
    }

    var body: some View {
        OnboardingScaffold(
            title: "Save your progress",
            subtitle: "Sign in with Apple or Google, or create an account with email, so you can invite \(onboarding.partnerName)",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    AppleGoogleSignInButtons(
                        onSuccess: { userID, providedFirstName in
                            Task { await finish(userID: userID, providedFirstName: providedFirstName) }
                        },
                        onError: { errorMessage = $0 },
                        isSubmitting: $isSubmitting
                    )

                    if showingEmailForm {
                        VStack(spacing: Theme.Spacing.md) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .padding()
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                            SecureField("Password", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                            SecureField("Confirm password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding()
                                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                            if passwordsMismatch {
                                Text("Passwords don't match")
                                    .font(.caption)
                                    .foregroundStyle(Theme.heartRed)
                            }

                            Button(action: continueWithEmail) {
                                if isSubmitting {
                                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                                } else {
                                    Text("Continue").font(.headline).frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                            .background(canContinueWithEmail && !isSubmitting ? Theme.skyBlue : Theme.subtleInk.opacity(0.3), in: Capsule())
                            .foregroundStyle(.white)
                            .disabled(!canContinueWithEmail || isSubmitting)
                        }
                    } else {
                        Button("Create an account with email") {
                            showingEmailForm = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.skyBlue)
                        .frame(maxWidth: .infinity)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }
                }
            }
        )
    }

    private func continueWithEmail() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                do {
                    try await BackendService.signUp(firstName: onboarding.firstName, email: email, password: password)
                } catch {
                    // Resuming onboarding after the app was closed mid-flow — fall back to
                    // signing in rather than dead-ending on "already registered".
                    try await BackendService.signIn(email: email, password: password)
                }
                guard let userID = BackendService.currentUserID else { throw BackendError.notAuthenticated }
                await finish(userID: userID, providedFirstName: nil)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func finish(userID: UUID, providedFirstName: String?) async {
        if let providedFirstName, !providedFirstName.isEmpty {
            onboarding.firstName = providedFirstName
        }
        await appModel.applyOnboardingAccount(onboarding)
        // `applyOnboardingAccount` finishes onboarding immediately (skipping the rest of the
        // flow) in the rare case where a real couple already existed — only advance otherwise.
        if !appModel.hasCouple {
            onboarding.path.append(.invitePartner)
        }
    }
}

#Preview {
    NavigationStack {
        SaveAccountView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
