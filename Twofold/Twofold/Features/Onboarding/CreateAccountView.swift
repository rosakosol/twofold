//
//  CreateAccountView.swift
//  Twofold
//
//  Used by the preserved deep-link/manual-invite path only — the default "Get started"
//  flow creates its account at the very end, via SaveAccountView.
//

import SwiftUI

struct CreateAccountView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var firstName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var isInvitee: Bool { onboarding.role == .invitee }

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
            && confirmPassword == password
    }

    var body: some View {
        OnboardingScaffold(
            title: isInvitee ? "Create your Twofold account" : "Create your account",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .onboardingFieldBackground()

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .onboardingFieldBackground()

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .onboardingFieldBackground()

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .onboardingFieldBackground()

                    if passwordsMismatch {
                        Text("Passwords don't match")
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }

                    HStack {
                        Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                        Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                        Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    AppleGoogleSignInButtons(
                        onSuccess: { userID, providedFirstName in
                            Task { await finishSignIn(userID: userID, providedFirstName: providedFirstName) }
                        },
                        onError: { errorMessage = $0 },
                        onAccountDeleted: { handleAccountDeleted() },
                        isSubmitting: $isSubmitting
                    )
                }
            },
            primaryTitle: "Continue",
            primaryAction: continueTapped,
            primaryDisabled: !canContinue || isSubmitting
        )
    }

    private func continueTapped() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                do {
                    try await BackendService.signUp(firstName: firstName, email: email, password: password)
                } catch {
                    // Most likely cause: this email already has an account — e.g. resuming
                    // onboarding after the app was closed mid-flow. Fall back to signing in
                    // rather than dead-ending on "already registered".
                    try await BackendService.signIn(email: email, password: password)
                }
                guard let userID = BackendService.currentUserID else { throw BackendError.notAuthenticated }
                await finishSignIn(userID: userID, providedFirstName: firstName)
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

    /// Lands both the email/password and provider sign-in paths in the same place: adopt the
    /// real identity locally, persist a first name if we have a better one than what's already
    /// on the profile, and advance onboarding.
    private func finishSignIn(userID: UUID, providedFirstName: String?) async {
        if let providedFirstName, !providedFirstName.isEmpty {
            try? await BackendService.updateFirstName(providedFirstName)
        }
        let resolvedName = (providedFirstName?.isEmpty == false) ? providedFirstName! : firstName
        appModel.adoptSignedInIdentity(id: userID, firstName: resolvedName)

        onboarding.firstName = resolvedName
        onboarding.hasAccount = true
        onboarding.path.append(.homeCity)
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
