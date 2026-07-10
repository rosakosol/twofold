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
            title: isInvitee ? "Join \(onboarding.inviterName ?? "your partner")" : "Create your account",
            subtitle: isInvitee ? "Just the basics — you can fill in the rest later." : "Keep it quick — first name, email, and a password.",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .textFieldStyle()

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle()

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .textFieldStyle()

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .textFieldStyle()

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
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
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

private extension View {
    func textFieldStyle() -> some View {
        self
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        CreateAccountView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
