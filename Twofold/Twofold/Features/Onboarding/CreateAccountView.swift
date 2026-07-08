//
//  CreateAccountView.swift
//  Twofold
//
//  Real Sign in with Apple/Google would use AuthenticationServices/GoogleSignIn and a
//  backend to actually create the account; both buttons here are mocked, matching the
//  approach used for SubscriptionStore — they just fill in a name and continue.
//

import SwiftUI

struct CreateAccountView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var firstName: String = ""
    @State private var email: String = ""
    @State private var password: String = ""

    private var isInvitee: Bool { onboarding.role == .invitee }

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
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

                    HStack {
                        Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                        Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                        Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                    }
                    .padding(.vertical, Theme.Spacing.xs)

                    mockProviderButton(title: "Continue with Apple", icon: "apple.logo")
                    mockProviderButton(title: "Continue with Google", icon: "g.circle.fill")
                }
            },
            primaryTitle: "Continue",
            primaryAction: continueTapped,
            primaryDisabled: !canContinue
        )
    }

    private func mockProviderButton(title: String, icon: String) -> some View {
        Button {
            if firstName.isEmpty { firstName = "Alex" }
            if email.isEmpty { email = "\(firstName.lowercased())@example.com" }
            password = "provider-auth"
            continueTapped()
        } label: {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .background(Theme.cardBackground, in: Capsule())
        .foregroundStyle(Theme.ink)
    }

    private func continueTapped() {
        onboarding.firstName = firstName
        onboarding.email = email
        onboarding.password = password
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
}
