//
//  BackendService+Auth.swift
//  Twofold
//
//  Sign-in, sign-up, passwords, Apple and Google, the session, and deleting the account.
//

import Foundation
import Supabase
import GoogleSignIn
import UIKit
import CryptoKit

extension BackendService {

    // MARK: - Auth

    @discardableResult
    static func signUp(firstName: String, email: String, password: String) async throws -> Session {
        let response = try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["first_name": .string(firstName)]
        )
        Analytics.capture(Analytics.Event.accountCreate, properties: ["method": "email"])
        let session: Session
        if let responseSession = response.session {
            session = responseSession
        } else {
            // Confirmations are disabled for this project, so a session should always come back
            // immediately; fall back to an explicit sign-in just in case that ever changes.
            session = try await supabase.auth.signIn(email: email, password: password)
        }
        try await rejectIfAccountDeleted()
        return session
    }

    @discardableResult
    static func signIn(email: String, password: String) async throws -> Session {
        let session = try await supabase.auth.signIn(email: email, password: password)
        try await rejectIfAccountDeleted()
        Analytics.capture(Analytics.Event.signIn, properties: ["method": "email"])
        return session
    }

    /// Shared guard for every sign-in/sign-up entry point in this section — Supabase's soft
    /// delete (`delete_own_account()`/the `delete-account` Edge Function) doesn't reliably block
    /// a *fresh* sign-in: email/password can still authenticate against the not-actually-removed
    /// `auth.users` row, and Apple/Google's id-token exchange looks up an existing `auth.identities`
    /// row by provider subject, which soft delete never touches either. Every path that just
    /// established a session checks this immediately and signs back out rather than letting a
    /// scrubbed, deleted profile ever be adopted — `AppModel.loadSignedInState()` has the
    /// equivalent guard for a *resumed* (not freshly established) session.
    private static func rejectIfAccountDeleted() async throws {
        guard await currentAccountIsDeleted() else { return }
        try? await supabase.auth.signOut()
        throw BackendError.accountDeleted
    }

    /// Never throws for "no account with that email" — Supabase deliberately responds the same
    /// way regardless, so a caller can't enumerate registered emails via this endpoint.
    ///
    /// `redirectTo` is a Universal Link, not the custom scheme this used to send. The custom
    /// scheme (`twofold://reset-password`) failed two ways at once. Supabase does not reject a
    /// `redirect_to` that is missing from the project's Redirect URLs allow-list — it silently
    /// substitutes the project's Site URL — so the emailed link quietly delivered people to the
    /// marketing site instead of anywhere useful. And a custom scheme means nothing in a desktop
    /// browser, so opening the email on a laptop led nowhere even when the allow-list was right.
    ///
    /// The https URL fixes both. iOS opens this app directly when it is installed (see the site's
    /// apple-app-site-association route, which now lists `/auth/reset-password`), and anyone
    /// without the app gets a real web form at the same address. `OnboardingCoordinatorView`'s
    /// `.onOpenURL` recognizes both shapes and calls `completePasswordRecovery(from:)` below;
    /// the custom scheme is still handled there because links already sitting in inboxes, and
    /// builds already installed, still use it.
    static func requestPasswordReset(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: URL(string: "https://www.twofoldapp.com.au/auth/reset-password"))
        Analytics.capture(Analytics.Event.passwordResetRequest)
    }

    /// Exchanges the token embedded in a tapped password-recovery link for a real (recovery)
    /// session — `session(from:)` handles both the implicit-grant (fragment) and PKCE (`code=`)
    /// link shapes transparently based on the project's configured auth flow, so this doesn't
    /// need to know or care which one is active. Throws for an invalid/expired/already-used link.
    static func completePasswordRecovery(from url: URL) async throws {
        try await supabase.auth.session(from: url)
    }

    /// Requires an active session, and has two callers with one each. `ResetPasswordView` runs it
    /// straight after `completePasswordRecovery(from:)`, on the session that emailed link just
    /// established. `AccountView` runs it on the ordinary signed-in session, for somebody changing
    /// a password they still know rather than recovering one they have lost.
    ///
    /// For an account created with Apple or Google this *sets* a password rather than replacing
    /// one: `encrypted_password` starts null and the provider lives in `auth.identities`, which
    /// this does not touch. They keep the provider button and gain an email/password route — under
    /// whatever address the account carries, which for Apple's Hide My Email is a relay nobody
    /// chose. `AccountView` shows that address directly above the form for exactly that reason.
    ///
    /// Assumes `secure_password_change = false` (config.toml). Turning it on would require a
    /// reauthentication nonce first, and this call would start failing for anyone whose sign-in is
    /// not recent.
    static func updatePassword(_ newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    /// Native Sign in with Apple. `nonce` is the raw (unhashed) nonce that was hashed into the
    /// original Apple authorization request — Supabase re-hashes and compares it against the
    /// token's own nonce claim to guard against replay.
    @discardableResult
    static func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        let session = try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        try await rejectIfAccountDeleted()
        Analytics.capture(Analytics.Event.signIn, properties: ["method": "apple"])
        return session
    }

    /// The ID token's `aud` claim matches whatever client ID *initiated* the sign-in request —
    /// which defaults to the iOS client (`GIDClientID` in Info.plist) unless a `serverClientID`
    /// is set. Supabase's Google provider is configured with the *Web* client (in the Supabase
    /// dashboard), so it rejects tokens audienced for the iOS client with "Unacceptable
    /// audience". Setting `serverClientID` here to that same Web client makes Google issue the
    /// token audienced correctly. See https://developers.google.com/identity/sign-in/ios/backend-auth.
    private static let googleWebClientID = "220566699855-1muier0anui8403ebqd5lpg3g288hima.apps.googleusercontent.com"

    /// Native Google Sign-In. `GIDClientID` (the iOS OAuth client) is read from Info.plist by
    /// the SDK automatically as the base configuration; `googleWebClientID` above is layered on
    /// as the `serverClientID` so Supabase can validate the resulting token.
    @discardableResult
    static func signInWithGoogle() async throws -> UUID {
        guard let presenter = topmostViewController() else { throw BackendError.notAuthenticated }
        guard let iosClientID = GIDSignIn.sharedInstance.configuration?.clientID
            ?? Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            throw BackendError.providerNotConfigured
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: iosClientID, serverClientID: googleWebClientID)

        // Unlike Sign in with Apple's SDK, GIDSignIn embeds whatever nonce it's given verbatim
        // into the ID token's `nonce` claim rather than hashing it first — so *we* need to hash
        // it before handing it to Google, then give Supabase the raw value so its own hash of
        // that matches the token's claim. Passing the same raw nonce to both (the previous bug
        // here) meant Supabase's hash of it could never equal the token's unhashed claim.
        let nonce = UUID().uuidString
        let hashedNonce = Self.sha256Hex(nonce)

        let result: GIDSignInResult = try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter, hint: nil, additionalScopes: nil, nonce: hashedNonce) { signInResult, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let signInResult {
                    continuation.resume(returning: signInResult)
                } else {
                    continuation.resume(throwing: BackendError.notAuthenticated)
                }
            }
        }

        guard let idToken = result.user.idToken?.tokenString else { throw BackendError.notAuthenticated }

        try await supabase.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: result.user.accessToken.tokenString,
                nonce: nonce
            )
        )
        try await rejectIfAccountDeleted()
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        Analytics.capture(Analytics.Event.signIn, properties: ["method": "google"])
        return userID
    }

    private static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func topmostViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// Restores a persisted session (if any) on launch. supabase-swift keeps the refresh
    /// token in the Keychain, so this succeeds silently across app relaunches.
    static func restoreSession() async -> Session? {
        try? await supabase.auth.session
    }

    static func signOut() async throws {
        try await supabase.auth.signOut()
    }

    /// Permanently deletes this account — calls the `delete-account` Edge Function (needs the
    /// service-role key to soft-delete the `auth.users` row, so it can't be done directly from
    /// the client). See that function's and `delete_own_account()`'s own doc comments for why
    /// this is a careful scoped cleanup rather than a blunt cascade delete: any couple this
    /// profile is part of is dissolved (not destroyed), so a partner's shared trip/memory
    /// history is never lost just because the other person deleted their own account.
    ///
    /// Sends no body. This used to pass `{"deleteSharedData": ...}` from the toggle on
    /// `DeleteAccountView`, which reached `delete_own_account(p_delete_shared_data)` — a
    /// parameter that has ignored its argument since
    /// 20261005000000_purge_is_only_ever_the_timer.sql made the 90-day archive clock the only
    /// route to deleting shared data. The flag was removed rather than reconnected; see that
    /// view's header.
    static func deleteAccount() async throws {
        guard let accessToken = await freshAccessToken() else { throw BackendError.notAuthenticated }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/delete-account"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.requestFailed(message: nil) }
        guard (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { var error: String? }
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw BackendError.requestFailed(message: message)
        }

        // supabase-swift keeps the refresh token in the Keychain across relaunches (see
        // `restoreSession()`), so without this the device stays silently signed in on a fully
        // valid local session even though the server-side account is gone — the app would
        // just resume straight back into the now-scrubbed profile. `auth.admin.deleteUser`'s
        // soft delete alone isn't enough to prevent that; it only marks `deleted_at` on
        // `auth.users`, it doesn't revoke an already-issued session.
        try? await supabase.auth.signOut()
    }

    /// True if this account was scrubbed by `delete_own_account()`. A backstop against the fact
    /// that Supabase Auth's soft delete doesn't reliably block a *fresh* sign-in — in particular,
    /// the Apple/Google id-token exchange looks up an existing `auth.identities` row by provider
    /// subject, which soft delete doesn't touch, so it can resolve straight back to the same
    /// deleted `auth.users` row and hand back a valid session. `AppModel.loadSignedInState()`
    /// calls this right after any session is established (launch restore, password sign-in, or
    /// Apple/Google sign-in) and signs back out immediately if it's true, rather than letting a
    /// deleted, scrubbed profile actually load.
    static func currentAccountIsDeleted() async -> Bool {
        guard let userID = currentUserID else { return false }
        struct Row: Decodable {
            var accountDeletedAt: String?
            enum CodingKeys: String, CodingKey { case accountDeletedAt = "account_deleted_at" }
        }
        do {
            let rows: [Row] = try await supabase
                .from("profiles")
                .select("account_deleted_at")
                .eq("id", value: userID)
                .limit(1)
                .execute()
                .value
            return rows.first?.accountDeletedAt != nil
        } catch {
            // The server refuses every request from a deleted account (20261114005000), this one
            // included, with "account_deleted". That refusal is the answer, not a failed check:
            // read as "not deleted", it left a deleted account signed in to a wall of errors.
            // Anything else (offline, a timeout) still means "don't know", so not deleted.
            return (error as? PostgrestError)?.message == "account_deleted"
        }
    }
}
