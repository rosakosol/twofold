//
//  AppleGoogleSignInButtons.swift
//  Twofold
//
//  Shared by CreateAccountView (mid-flow, deep-link/invite path) and SaveAccountView
//  (end of the default onboarding flow) so the nonce/button-styling logic isn't
//  duplicated. The caller decides what happens after a successful sign-in.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import GoogleSignIn
import UIKit

struct AppleGoogleSignInButtons: View {
    /// Apple only ever hands over a name on the very first authorization — passed through
    /// when available so the caller can use it if it doesn't have a better one already.
    var onSuccess: (_ userID: UUID, _ providedFirstName: String?) -> Void
    var onError: (String) -> Void
    @Binding var isSubmitting: Bool

    @State private var currentAppleNonce: String = ""

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.continue, onRequest: configureAppleRequest, onCompletion: handleAppleCompletion)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(Capsule())

            Button(action: continueWithGoogle) {
                HStack(spacing: 10) {
                    if let googleLogo {
                        googleLogo
                            .resizable()
                            .frame(width: 18, height: 18)
                    }
                    Text("Sign in with Google")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x1F / 255))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .background(
                Capsule()
                    .fill(Color.white)
                    .overlay(
                        Capsule().strokeBorder(Color(red: 0x74 / 255, green: 0x77 / 255, blue: 0x75 / 255), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Sign in with Apple

    private func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        isSubmitting = true
        Task {
            do {
                guard case .success(let authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    throw BackendError.notAuthenticated
                }

                try await BackendService.signInWithApple(idToken: idToken, nonce: currentAppleNonce)
                guard let userID = BackendService.currentUserID else { throw BackendError.notAuthenticated }
                onSuccess(userID, credential.fullName?.givenName)
            } catch {
                onError(error.localizedDescription)
            }
            isSubmitting = false
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate a secure nonce")
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Google sign-in

    private func continueWithGoogle() {
        isSubmitting = true
        Task {
            do {
                let userID = try await BackendService.signInWithGoogle()
                onSuccess(userID, nil)
            } catch {
                onError(error.localizedDescription)
            }
            isSubmitting = false
        }
    }

    /// The official multicolor "G" mark, reused directly from the GoogleSignIn SDK's own
    /// bundled asset rather than approximated, so the button stays brand-accurate.
    private var googleLogo: Image? {
        guard let bundlePath = Bundle(for: GIDSignIn.self).path(forResource: "GoogleSignIn_GoogleSignIn", ofType: "bundle"),
              let resourceBundle = Bundle(path: bundlePath),
              let iconPath = resourceBundle.path(forResource: "google", ofType: "png"),
              let uiImage = UIImage(contentsOfFile: iconPath) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }
}
