//
//  LegalConsentCheckbox.swift
//  Twofold
//
//  The one place anyone agrees to anything. Shown on every screen that can create an account —
//  `CreateAccountView`, `SaveAccountView`, and `SignInView`, which belongs in that list because
//  Sign in with Apple or Google against an address with no account *creates* one, whatever the
//  screen is called.
//
//  It carries two claims in one control:
//
//    - Age. Both documents say 16 and nothing in the app asked, so until this existed the policy
//      stated a rule the product did not apply.
//    - Assent to the Terms and the Privacy Policy, which the terms themselves assume ("By
//      creating an account ... you're agreeing to them") and which onboarding never collected.
//
//  Bundling the two is fine here: the policy's lawful bases are contract and legitimate
//  interests, not consent, so this is an attestation plus assent rather than GDPR consent being
//  bundled with something else.
//
//  The links open `LegalDocumentSheet` in-app rather than throwing the reader out to Safari
//  mid-signup. They are markdown inside a single `Text` rather than buttons spliced into an
//  HStack so that the sentence wraps like a sentence at any Dynamic Type size.
//

import SwiftUI

/// The sentence itself, with the two links wired to open in-app.
///
/// Markdown inside a single `Text` rather than buttons spliced into an `HStack` so that it wraps
/// like a sentence at any Dynamic Type size.
private struct LegalSentence: View {
    let markdown: String
    let plain: String
    @Binding var presentedDocument: LegalDocument?

    var body: some View {
        Text((try? AttributedString(markdown: markdown)) ?? AttributedString(plain))
            .font(.footnote)
            .foregroundStyle(Theme.subtleInk)
            .tint(Theme.skyBlueText)
            .fixedSize(horizontal: false, vertical: true)
            // Catches the `legal://` links. Anything else is handed back to the system untouched,
            // so a real URL added to one of these sentences later still behaves like one.
            .environment(\.openURL, OpenURLAction { url in
                guard let document = LegalDocument.fromLinkURL(url) else { return .systemAction }
                presentedDocument = document
                return .handled
            })
    }
}

/// Passive notice for `SignInView`, which is a sign-in screen and not an account-creation one.
///
/// Deliberately not the checkbox. Email sign-in there reaches `BackendService.signIn`, which
/// cannot create anything — so the person in front of it already has an account and already
/// accepted these, and a tick box would be asking them to do it again every time they sign in on
/// a new device. The reason it says anything at all is the narrow case at the bottom of that
/// screen: Sign in with Apple or Google against an address with no account does create one. This
/// covers that with sign-in-wrap assent rather than putting a gate in front of everybody else.
struct LegalConsentNotice: View {
    @State private var presentedDocument: LegalDocument?

    var body: some View {
        LegalSentence(
            markdown: "By continuing you confirm you're 16 or over, and agree to the [Terms of Use](legal://terms) and [Privacy Policy](legal://privacy).",
            plain: "By continuing you confirm you're 16 or over, and agree to the Terms of Use and Privacy Policy.",
            presentedDocument: $presentedDocument
        )
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSheet(document: document).ignoresSafeArea()
        }
    }
}

struct LegalConsentCheckbox: View {
    @Binding var isAccepted: Bool

    @State private var presentedDocument: LegalDocument?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
            Button {
                isAccepted.toggle()
            } label: {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isAccepted ? Theme.skyBlueText : Theme.subtleInk)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I'm 16 or over, and I agree to the Terms of Use and Privacy Policy")
            .accessibilityAddTraits(.isToggle)

            LegalSentence(
                markdown: "I'm 16 or over, and I agree to the [Terms of Use](legal://terms) and [Privacy Policy](legal://privacy).",
                plain: "I'm 16 or over, and I agree to the Terms of Use and Privacy Policy.",
                presentedDocument: $presentedDocument
            )

            Spacer(minLength: 0)
        }
        .sheet(item: $presentedDocument) { document in
            LegalDocumentSheet(document: document).ignoresSafeArea()
        }
    }
}

#Preview {
    @Previewable @State var accepted = false
    return VStack(spacing: Theme.Spacing.lg) {
        LegalConsentCheckbox(isAccepted: $accepted)
        LegalConsentCheckbox(isAccepted: .constant(true))
        LegalConsentNotice()
    }
    .padding()
}
