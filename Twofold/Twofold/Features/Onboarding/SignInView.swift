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

import Supabase
import SwiftUI

struct SignInView: View {
    /// Called when the user says they have an invite code rather than an existing account —
    /// the presenter (WelcomeView) dismisses this sheet and routes onboarding into the
    /// invitee flow. Optional so the preview / other call sites can omit it.
    var onUseInvite: (() -> Void)?

    @Environment(AppModel.self) private var appModel
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(\.dismiss) private var dismiss

    @State private var email: String
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingForgotPassword = false

    /// Prefills the email field — used when a signup attempt elsewhere in onboarding discovers
    /// the email already has an account and redirects here, so the user isn't asked to retype
    /// what they just typed a moment ago.
    init(initialEmail: String = "", onUseInvite: (() -> Void)? = nil) {
        _email = State(initialValue: initialEmail)
        self.onUseInvite = onUseInvite
    }

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
                        AuthField(
                            title: "Email",
                            text: $email,
                            textContentType: .emailAddress,
                            keyboardType: .emailAddress
                        )

                        AuthField(
                            title: "Password",
                            text: $password,
                            isSecure: true,
                            textContentType: .password
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRedText)
                        }

                        Button {
                            showingForgotPassword = true
                        } label: {
                            Text("Forgot password?")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.skyBlueText)
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
                        .background(canSubmit ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.subtleInk.opacity(0.3)), in: Capsule())
                        .foregroundStyle(.white)
                        .disabled(!canSubmit)

                        HStack {
                            Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                            Text("or").font(.caption).foregroundStyle(Theme.subtleInk)
                            Rectangle().fill(Theme.subtleInk.opacity(0.2)).frame(height: 1)
                        }
                        .padding(.vertical, Theme.Spacing.xs)

                        AppleGoogleSignInButtons(
                            onSuccess: { _, _ in Task { await finishSignIn(viaProvider: true) } },
                            onError: { errorMessage = $0 },
                            onAccountDeleted: { handleAccountDeleted() },
                            isSubmitting: $isSubmitting
                        )

                        if let onUseInvite {
                            Button {
                                onUseInvite()
                            } label: {
                                Text("Have an invite code instead?")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.skyBlueText)
                            }
                            .padding(.top, Theme.Spacing.sm)
                        }

                        // Signing in cannot create an account; the two provider buttons above
                        // can, for an address that has none. See `LegalConsentNotice`.
                        LegalConsentNotice()
                            .padding(.top, Theme.Spacing.md)
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
                await finishSignIn(viaProvider: false)
            } catch {
                if case BackendError.accountDeleted = error {
                    handleAccountDeleted()
                } else {
                    errorMessage = Self.signInFailureMessage(for: error)
                }
                isSubmitting = false
            }
        }
    }

    /// Shared by both the email/password and Apple/Google paths. No explicit `dismiss()` —
    /// once `loadSignedInState` flips `hasCouple`, `RootView` swaps its whole body to
    /// `MainTabView`, tearing this sheet's presenter down along with it.
    private func finishSignIn(viaProvider: Bool) async {
        await appModel.loadSignedInState()
        // Defense in depth for a stale/resumed session specifically — a *fresh* sign-in
        // attempt is already rejected earlier now (`BackendService`'s sign-in methods each
        // throw `.accountDeleted` before ever reaching here), which is what `signInWithPassword`
        // and the Apple/Google `onAccountDeleted` callback above actually handle.
        if appModel.accountDeletedMessage != nil {
            handleAccountDeleted()
            return
        }
        // Apple/Google auto-provision a brand-new account on first use — unlike email/password
        // (wrong credentials just fail), there is no "no such account" error to tell a genuinely
        // new person apart from a returning one here.
        //
        // This used to test `currentUser.name.isEmpty`, reasoning that onboarding collects a name
        // before the account exists, so a nameless profile cannot have onboarded. The test could
        // never fire: `fetchOwnProfile` and `adoptSignedInIdentity` both substitute "You" for an
        // empty name, so the property is never empty. The premise was wrong as well —
        // `applyOnboardingAccount` never persisted the name on the Apple/Google paths, so an empty
        // `first_name` was the normal state for an SSO account that had fully onboarded.
        //
        // `needsOnboarding` is the recorded fact (migration 20261106000000), not a guess.
        if appModel.needsOnboarding {
            // Only on the provider paths, and the comment above is the reason: auto-provisioning is
            // a thing Apple and Google do. Email and password cannot create an account here — a
            // wrong address fails as `invalid_credentials` and never reaches this line — so on that
            // path `needsOnboarding` never means "we made you a new one". It means the account they
            // just proved they own has not finished onboarding.
            //
            // Said to everyone, the message was a flat untruth to the larger group. Anybody who
            // quit onboarding between creating their account and the paywall — which is most of
            // this branch's real traffic, because the account is created at `.saveAccount`, several
            // screens before the paywall — signed back in with the exact email and password they
            // had just chosen, and was told their Apple or Google account was not linked, that a
            // new account had been started, and to go and sign in with some other address. There is
            // no other address. Their account was found, and it was theirs.
            //
            // They are still routed into onboarding either way; `RootView` does that off
            // `needsOnboarding` the moment this sheet closes. The only thing that changes here is
            // whether they are handed an explanation that does not apply to them.
            if viaProvider {
                // Somebody on a screen titled "Welcome back" did not mean to create an account, so
                // say that one has been created. Overwhelmingly this is Hide My Email: the relay
                // address is a new email, so it is a new user, and their real account is still
                // sitting there holding the couple and the history.
                appModel.signedInToNewAccountMessage = "This Apple ID or Google account wasn't linked to a Twofold account, so we've started a new one for you.\n\nIf you already have an account it was made with a different email address — especially likely if you chose \"Hide My Email\". Sign out from Settings and sign in with that email to get back to it."
            }
            dismiss()
            return
        }
        isSubmitting = false
    }

    /// Supabase answers a wrong password and an address that has no password at all with the same
    /// `invalid_credentials`, deliberately — telling them apart would be an oracle for which
    /// emails are registered. Right for the API, a dead end for the person, because the likeliest
    /// reason a real user is stuck here is that their account has no password to get wrong: they
    /// created it with Apple or Google, both offered on this very screen.
    ///
    /// So the hint is attached to the generic failure rather than to a detected one. It reveals
    /// nothing — a mistyped password on an email account gets it too — and it names the thing that
    /// actually fixes it.
    static func signInFailureMessage(for error: Error) -> String {
        guard let authError = error as? AuthError, authError.errorCode == .invalidCredentials else {
            return error.localizedDescription
        }
        return "That email and password don't match an account. If you signed up with Apple or Google, use those buttons above instead — those accounts don't have a password."
    }

    /// Redirects straight into a fresh onboarding flow instead of leaving this sheet showing a
    /// dead-end error — see `OnboardingModel.resetAfterDeletedAccount()`. `WelcomeView` shows
    /// `appModel.accountDeletedMessage` once as a friendly alert after this sheet dismisses.
    private func handleAccountDeleted() {
        if appModel.accountDeletedMessage == nil {
            appModel.accountDeletedMessage = "That account has been deleted. Create a new account to keep using Twofold."
        }
        onboarding.resetAfterDeletedAccount()
        isSubmitting = false
        dismiss()
    }
}

#Preview {
    SignInView()
        .environment(AppModel())
        .environment(OnboardingModel())
}
