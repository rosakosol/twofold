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

import Supabase
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
    /// Set when `signUp` fails specifically because this email already has an account — reveals
    /// a "Sign In" button rather than silently retrying with whatever password was just typed
    /// into *this* form, which almost always isn't that account's real password.
    @State private var emailAlreadyExists = false
    @State private var showingSignIn = false

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var canContinueWithEmail: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
            && confirmPassword == password
            && PasswordStrength.evaluate(password) > .weak
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
                        onAccountDeleted: { handleAccountDeleted() },
                        isSubmitting: $isSubmitting
                    )

                    if showingEmailForm {
                        VStack(spacing: Theme.Spacing.md) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .padding()
                                .onboardingFieldBackground()

                            SecureField("Password", text: $password)
                                .textContentType(.newPassword)
                                .padding()
                                .onboardingFieldBackground()

                            PasswordStrengthView(password: password)

                            SecureField("Confirm password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .padding()
                                .onboardingFieldBackground()

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

                            if emailAlreadyExists {
                                Button {
                                    showingSignIn = true
                                } label: {
                                    Text("Sign In")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.skyBlue)
                                }
                            }
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
        .sheet(isPresented: $showingSignIn) {
            SignInView(initialEmail: email)
        }
    }

    private func continueWithEmail() {
        isSubmitting = true
        errorMessage = nil
        emailAlreadyExists = false
        Task {
            do {
                try await BackendService.signUp(firstName: onboarding.firstName, email: email, password: password)
                guard let userID = BackendService.currentUserID else { throw BackendError.notAuthenticated }
                await finish(userID: userID, providedFirstName: nil)
            } catch let authError as AuthError where authError.errorCode == .emailExists {
                // Don't silently retry as a sign-in — the password just typed into *this* form
                // is almost never that existing account's real password, so that attempt would
                // just fail again with a confusing "wrong password" error. Directing to a real
                // sign-in screen (prefilled with the same email) lets them enter their actual
                // credentials instead.
                errorMessage = "An account with this email already exists."
                emailAlreadyExists = true
            } catch {
                if case BackendError.accountDeleted = error {
                    handleAccountDeleted()
                } else {
                    errorMessage = error.localizedDescription
                }
            }
            isSubmitting = false
        }
    }

    /// Redirects straight into a fresh onboarding flow instead of leaving this screen showing a
    /// dead-end error — see `OnboardingModel.resetAfterDeletedAccount()`. Resetting `onboarding.
    /// path` to empty pops this view itself back to `WelcomeView`, which shows
    /// `appModel.accountDeletedMessage` once as a friendly alert.
    private func handleAccountDeleted() {
        appModel.accountDeletedMessage = "That account has been deleted. Create a new account to keep using Twofold."
        onboarding.resetAfterDeletedAccount()
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
