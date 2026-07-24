//
//  SignInView.swift
//  Twofold
//
//  Presented from WelcomeView for a returning user with no local session (fresh install,
//  new device, or after an explicit sign-out) — a normal app relaunch restores the session
//  automatically via `AppModel.restoreSession`, so this is only needed when that silent
//  restore has nothing to work with. On success, `loadSignedInState` loads real couple/solo
//  state and flips `hasCouple`, which `RootView` picks up to swap straight to `MainTabView`
//  — skipping onboarding entirely, since signing in already proves the account exists.
//

import SwiftUI

struct SignInView: View {
    /// Called when the user says they have an invite code rather than an existing account —
    /// the presenter (WelcomeView) dismisses this sheet and routes onboarding into the
    /// invitee flow. Optional so the preview / other call sites can omit it.
    var onUseInvite: (() -> Void)?

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingForgotPassword = false

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text("Welcome back")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text("Sign in to pick up right where you left off.")
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

                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRed)
                        }

                        Button {
                            showingForgotPassword = true
                        } label: {
                            Text("Forgot password?")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.skyBlue)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)

                        Button {
                            signInWithPassword()
                        } label: {
                            if isSubmitting {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Text("Sign In").font(.headline).frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(canSubmit ? Theme.skyBlue : Theme.subtleInk.opacity(0.3), in: Capsule())
                        .foregroundStyle(.white)
                        .disabled(!canSubmit)

                        HStack {
                            Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                            Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                            Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                        }
                        .padding(.vertical, Theme.Spacing.xs)

                        AppleGoogleSignInButtons(
                            onSuccess: { _, _ in Task { await finishSignIn() } },
                            onError: { errorMessage = $0 },
                            isSubmitting: $isSubmitting
                        )

                        if let onUseInvite {
                            Button {
                                onUseInvite()
                            } label: {
                                Text("Have an invite code instead?")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.skyBlue)
                            }
                            .padding(.top, Theme.Spacing.sm)
                        }
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
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
            }
        }
    }

    private func signInWithPassword() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await BackendService.signIn(email: email, password: password)
                await finishSignIn()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    /// Shared by both the email/password and Apple/Google paths. No explicit `dismiss()` —
    /// once `loadSignedInState` flips `hasCouple`, `RootView` swaps its whole body to
    /// `MainTabView`, tearing this sheet's presenter down along with it.
    private func finishSignIn() async {
        await appModel.loadSignedInState()
        isSubmitting = false
    }
}

#Preview {
    SignInView()
        .environment(AppModel())
}
