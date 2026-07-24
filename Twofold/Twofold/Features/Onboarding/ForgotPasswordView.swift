//
//  ForgotPasswordView.swift
//  Twofold
//
//  Sheeted from SignInView's "Forgot password?" link. Sends the recovery email via
//  BackendService.requestPasswordReset — the actual link tap is handled by
//  OnboardingCoordinatorView's .onOpenURL (twofold://reset-password), which routes into
//  ResetPasswordView once the recovery token's been exchanged for a session.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Forgot your password?")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Enter your account email and we'll send you a link to reset it.")
                            .font(.body)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Spacing.lg)

                    VStack(spacing: Theme.Spacing.md) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRed)
                        }

                        Button {
                            send()
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Text("Send Reset Link").font(.headline).frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(canSubmit ? Theme.skyBlue : Theme.subtleInk.opacity(0.3), in: Capsule())
                        .foregroundStyle(.white)
                        .disabled(!canSubmit)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Deliberately non-committal about whether the address is actually registered —
            // Supabase itself never reveals that (same response either way, so a caller can't
            // enumerate real accounts), so claiming "sent!" outright would just be a lie for an
            // unregistered email.
            .alert("Check your email", isPresented: $didSend) {
                Button("Done") { dismiss() }
            } message: {
                Text("If an account exists for \(email), we've sent a link to reset your password.")
            }
        }
    }

    private func send() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await BackendService.requestPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                isSubmitting = false
                didSend = true
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
}
