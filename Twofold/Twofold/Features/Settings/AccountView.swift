//
//  AccountView.swift
//  Twofold
//
//  The sign-in itself — which address this account is, and the password that opens it.
//
//  Neither was visible anywhere before. The address mattered most: an account can be created with
//  email, with Apple, or with Google, and Apple's Hide My Email hands back a relay address nobody
//  chose and nobody remembers. `SignInView` already has to explain that to people who cannot get
//  back in ("it was made with a different email address — especially likely if you chose Hide My
//  Email"), and the address it is talking about was, until now, not shown anywhere in the app.
//
//  Password changing lives here rather than behind a forgotten-password email, because needing a
//  reset link to change a password you still know is a strange thing to ask of somebody who is
//  already signed in. The emailed route stays for people who are locked out — see
//  `ForgotPasswordView` and `ResetPasswordView`, which run the same `updatePassword` at the end.
//
//  It is shown only to accounts that actually have a password. Supabase would happily *set* one on
//  an Apple or Google account — `encrypted_password` starts null and filling it changes nothing
//  else — and offering that looked like a kindness until you follow it through. The password would
//  only work alongside the address the account carries, and for Apple's Hide My Email that is a
//  `@privaterelay.appleid.com` relay the person has never typed and will not recognise. A login
//  they cannot perform from memory is not a recovery route.
//
//  The usual argument for offering it anyway is losing access to the provider. That is weak here
//  too: the relay forwards to the Apple ID, so whoever has lost the Apple ID has lost the email
//  with it.
//

import PostHog
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var appModel

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Kept apart from `errorMessage` so a success is not announced in red under a failure's
    /// heading — the same split `PaywallView` makes between `restoreNotice` and `errorMessage`.
    @State private var successMessage: String?
    /// Nil until the picker is used, so an account with no birthday shows the prompt rather than
    /// today's date pre-selected — which would read as a value somebody had chosen.
    @State private var birthdayDate: Date?

    private var passwordsMismatch: Bool {
        !confirmPassword.isEmpty && confirmPassword != newPassword
    }

    /// Whether this account has a password at all.
    ///
    /// Asks for "email" rather than asking whether a provider is present, because those differ for
    /// anyone holding both — somebody who signed up with an address and later also used Apple has
    /// a real password, and hiding the form from them would strand it.
    private var hasPasswordSignIn: Bool {
        BackendService.currentUserSignInProviders.contains("email")
    }

    /// The providers this account can sign in with, named the way their buttons are.
    private var providerNames: [String] {
        BackendService.currentUserSignInProviders.compactMap { provider in
            switch provider {
            case "apple": "Apple"
            case "google": "Google"
            case "email": nil
            default: provider.capitalized
            }
        }
    }

    /// Deliberately the same bar `SaveAccountView` sets for a new account, rather than a lower one
    /// because this is "only" a change. A password set here is the account's real password from
    /// then on, so letting it be weaker than one chosen at signup would just move the weak spot.
    private var canSave: Bool {
        confirmPassword == newPassword
            && PasswordPolicy.isAcceptable(newPassword, email: BackendService.currentUserEmail)
            && !isSaving
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("Email").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    // Selectable, because the whole point of showing it is that somebody may need
                    // to write it down, paste it into a password manager, or read it to support.
                    Text(BackendService.currentUserEmail ?? "—")
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("This is the address you sign in with. It can't be changed here — contact us from Settings → Help if you need it moved.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }

                birthdaySection

                if hasPasswordSignIn {
                    passwordSection
                } else {
                    providerSection
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Account")
        .onAppear { birthdayDate = appModel.couple.partnerA.birthday?.date() }
    }

    /// Your own birthday. Optional here, as it is everywhere it is asked for.
    ///
    /// Only ever your own — your partner's is shown on their screen, sourced from their row, and
    /// there is nowhere in the app to type a birthday on somebody else's behalf. See
    /// `AppModel.updateBirthday`.
    private var birthdaySection: some View {
        SectionCard {
            Text("Birthday").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)

            if let birthdayDate {
                DatePicker(
                    "Birthday",
                    selection: Binding(get: { birthdayDate }, set: { saveBirthday(Birthday(date: $0)) }),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Remove birthday", role: .destructive) { saveBirthday(nil) }
                    .font(.caption)
            } else {
                Button("Add your birthday") {
                    // Seeded rather than saved — opening a picker is not the same as choosing a
                    // date, so nothing is written until the picker is actually moved.
                    birthdayDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))
                }
                .font(.body)
            }

            // Said once, here, because "we only store the day" is the kind of claim people
            // reasonably want to see before typing a date of birth into anything.
            Text("We only keep the day and month — never the year. \(appModel.partner.name) will see it so they don't miss it.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Only for accounts that have a password. See this file's header for why an Apple or Google
    /// account is not offered one.
    private var passwordSection: some View {
        SectionCard {
            Text("Change password").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)

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
            if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.success)
            }

            Button(action: save) {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Update password").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }

    /// What an Apple or Google account sees instead: a statement of how they get in.
    ///
    /// Worth a row of its own rather than nothing at all. "No password here" is only useful next to
    /// the reason, and somebody who cannot remember how they signed up has no other way to find out
    /// — the sign-in screen offers all three buttons and does not say which one is theirs.
    private var providerSection: some View {
        SectionCard {
            Text("How you sign in").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            if providerNames.isEmpty {
                // Identities missing from the cached session. Not evidence of anything, so this
                // claims nothing and points at the route that works either way.
                Text("You can reset your password from the sign-in screen using \"Forgot password\".")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("You sign in with \(providerNames.formatted(.list(type: .or))), use the same button next time you sign in.")
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    private func saveBirthday(_ birthday: Birthday?) {
        birthdayDate = birthday?.date()
        Task { await appModel.updateBirthday(birthday) }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        Task {
            do {
                try await BackendService.updatePassword(newPassword)
                // Cleared on success so the screen cannot be left holding the new password in two
                // visible fields, and so a second tap cannot re-send it.
                newPassword = ""
                confirmPassword = ""
                successMessage = "Password updated."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        AccountView()
    }
    .environment(AppModel())
}
