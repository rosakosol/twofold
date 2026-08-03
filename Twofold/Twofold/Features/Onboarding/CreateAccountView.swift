//
//  CreateAccountView.swift
//  Twofold
//
//  Used by the preserved deep-link/manual-invite path only — the default "Get started"
//  flow creates its account at the very end, via SaveAccountView.
//

import Supabase
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
    /// Set when `signUp` fails specifically because this email already has an account — reveals
    /// a "Sign In" button rather than silently retrying with whatever password was just typed
    /// into *this* form, which almost always isn't that account's real password.
    @State private var emailAlreadyExists = false
    @State private var showingSignIn = false

    private var isInvitee: Bool { onboarding.role == .invitee }

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != password
    }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
            && confirmPassword == password
            && PasswordStrength.evaluate(password) > .weak
    }

    var body: some View {
        OnboardingScaffold(
            title: isInvitee ? "Create your Twofold account" : "Create your account",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .padding()
                        .onboardingFieldBackground()

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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.heartRed)
                    }

                    if emailAlreadyExists {
                        Button {
                            showingSignIn = true
                        } label: {
                            Text("Sign In")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.skyBlue)
                        }
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
        .sheet(isPresented: $showingSignIn) {
            SignInView(initialEmail: email)
        }
    }

    private func continueTapped() {
        isSubmitting = true
        errorMessage = nil
        emailAlreadyExists = false
        Task {
            do {
                try await BackendService.signUp(firstName: firstName, email: email, password: password)
                guard let userID = BackendService.currentUserID else { throw BackendError.notAuthenticated }
                await finishSignIn(userID: userID, providedFirstName: firstName)
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
