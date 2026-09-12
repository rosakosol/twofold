//
//  LegalDocumentSheet.swift
//  Twofold
//
//  The Terms of Use and Privacy Policy, shown inside the app rather than handed to the browser.
//
//  `SFSafariViewController` over a native renderer deliberately. Both documents are authored in
//  Sanity and published to twofoldapp.com.au (site/scripts/seed-privacy-policy.mjs and
//  seed-terms.mjs); a bundled copy inside the app would be a fourth place for the same statements
//  to go stale, after the policy, the terms and the FAQ entries — which is exactly the failure
//  this was all written to fix. This renders whatever is published, so it cannot disagree with
//  the website.
//
//  It needs a network. Acceptable here: every screen that offers these links is a screen where
//  you are about to create an account, which needs one anyway.
//

import SafariServices
import SwiftUI

enum LegalDocument: String, Identifiable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Terms of Use"
        case .privacy: "Privacy Policy"
        }
    }

    var url: URL {
        switch self {
        case .terms: URL(string: "https://www.twofoldapp.com.au/terms")!
        case .privacy: URL(string: "https://www.twofoldapp.com.au/privacy")!
        }
    }

    /// Resolves the `legal://` links embedded in `LegalConsentCheckbox`'s sentence.
    ///
    /// A scheme the app deliberately does not register. `OpenURLAction` intercepts these before
    /// the system ever sees them, and if that interception were ever removed, an unhandled
    /// `legal://` link does nothing at all — whereas a `twofold://` one would be picked up by the
    /// app's real deep-link handling in `RootView`/`OnboardingCoordinatorView` and try to redeem
    /// an invite or start a password reset.
    static func fromLinkURL(_ url: URL) -> LegalDocument? {
        guard url.scheme == "legal" else { return nil }
        return LegalDocument(rawValue: url.host ?? "")
    }
}

/// `SFSafariViewController` as a sheet — same representable shape as `CameraPicker`.
struct LegalDocumentSheet: UIViewControllerRepresentable {
    let document: LegalDocument

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        // Reader would strip the page's own structure — these are long documents whose headings
        // are how anyone finds the section they came for.
        configuration.entersReaderIfAvailable = false

        let controller = SFSafariViewController(url: document.url, configuration: configuration)
        controller.dismissButtonStyle = .done
        controller.preferredControlTintColor = UIColor(Theme.skyBlue)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
