//
//  ResetPasswordView.swift
//  Twofold
//
//  Presented (fullScreenCover, from OnboardingCoordinatorView) once a tapped password-recovery
//  link's token has already been exchanged for a real session via
//  BackendService.completePasswordRecovery(from:) — this screen only ever needs to set the new
//  password against that already-established session.
//

import SwiftUI

struct ResetPasswordView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    /// The same bar signup sets. It used to be `count >= 6` and nothing else, which made this the
    /// way around the password rule rather than a way back into the account: anyone could reset to
    /// "123456" from an email link, and for somebody who signed up on the website with a one-time
    /// link this is the *first* password their account has ever had.
    private var canSubmit: Bool {
        newPassword == confirmPassword
            && PasswordPolicy.isAcceptable(newPassword, email: BackendService.currentUserEmail)
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Set a new password")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Choose a new password for your account.")
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.md) {
                        AuthField(
                            title: "New password",
                            text: $newPassword,
                            isSecure: true,
                            textContentType: .newPassword
                        )

                        PasswordStrengthView(password: newPassword, email: BackendService.currentUserEmail)

                        AuthField(
                            title: "Confirm password",
                            text: $confirmPassword,
                            isSecure: true,
                            textContentType: .newPassword
                        )

                        if passwordsMismatch {
                            Text("Passwords don't match.")
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        }

                        Button {
                            save()
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(Theme.onPrimaryButton).frame(maxWidth: .infinity)
                            } else {
                                Text("Save Password").font(.headline).frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(canSubmit ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.textSecondary.opacity(0.3)), in: Capsule())
                        .foregroundStyle(Theme.onPrimaryButton)
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Bails out of the just-established recovery session rather than leaving it
                    // dangling — there's no sensible "cancel and go back to where I was" here
                    // since tapping the email link is what got us into a session in the first
                    // place.
                    Button("Cancel") {
                        Task {
                            try? await BackendService.signOut()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func save() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await BackendService.updatePassword(newPassword)
                // No explicit dismiss — once loadSignedInState flips hasCouple, RootView swaps
                // its whole body away from OnboardingCoordinatorView (whose fullScreenCover this
                // is), tearing this down along with it. Same pattern SignInView.finishSignIn()
                // already relies on.
                await appModel.loadSignedInState()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

#Preview {
    ResetPasswordView()
        .environment(AppModel())
}
