//
//  InviteCode.swift
//  Twofold
//
//  Sharing/parsing helpers for partner invite links. The actual code is always issued by the
//  backend (`create_invite_code` RPC, fully random letters — carries no name information) and
//  validated on redeem (`redeem_invite_code` RPC) — this type only builds/parses the URL around
//  it. The inviter's display name/avatar is a real backend lookup now
//  (`BackendService.inviterInfo(forCode:)`), not something guessable from the code's own text.
//
//  Shared as a Universal Link (`https://www.twofoldapp.com.au/invite/CODE`) so it also works for
//  someone who doesn't have Twofold installed yet — tapping it opens the app directly if
//  installed, or falls back to the plain URL (a web landing page) if not, which a bare custom
//  scheme can never do. Requires an apple-app-site-association file hosted at
//  https://www.twofoldapp.com.au/.well-known/apple-app-site-association (see project setup
//  notes) and the com.apple.developer.associated-domains entitlement (Twofold.entitlements).
//  The old `twofold://invite/CODE` custom-scheme format is still parsed for backward
//  compatibility with any already-shared links.
//

import Foundation

enum InviteCode {
    static let universalLinkHost = "www.twofoldapp.com.au"

    static func shareURL(for code: String) -> URL {
        URL(string: "https://\(universalLinkHost)/invite/\(code)")!
    }

    /// Parses either `https://www.twofoldapp.com.au/invite/<CODE>` (current) or
    /// `twofold://invite/<CODE>` (legacy custom-scheme links already shared before Universal
    /// Links were wired up).
    static func code(from url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.contains(where: { $0.lowercased() == "invite" }) else { return nil }

        let isUniversalLink = url.scheme?.lowercased() == "https" && url.host?.lowercased() == universalLinkHost
        let isLegacyCustomScheme = url.scheme?.lowercased() == "twofold"
        guard isUniversalLink || isLegacyCustomScheme else { return nil }

        if url.host?.lowercased() == "invite", let code = components.first {
            return code.uppercased()
        }
        if let code = components.last {
            return code.uppercased()
        }
        return nil
    }

    /// Live-formats manual code entry to match the real `XXXX-XXXX` shape as you type — strips
    /// anything that isn't a letter (so pasting a code with its dash already in place, or in
    /// lowercase, still works), uppercases, and inserts the dash as soon as the 4th letter is
    /// typed (not retroactively once a 5th arrives). Capped at 8 letters, the real code length.
    ///
    /// `isDeleting` (pass whether `input` is shorter than whatever was there a moment ago)
    /// suppresses that same auto-insert on backspace — without it, deleting the dash right after
    /// "ABCD-" would immediately snap back to "ABCD-", since 4 letters alone would otherwise
    /// always trigger it again, making the dash impossible to backspace past.
    static func autoFormat(_ input: String, isDeleting: Bool) -> String {
        let letters = input.uppercased().filter { $0.isLetter }
        let limited = String(letters.prefix(8))
        let threshold = isDeleting ? 5 : 4
        guard limited.count >= threshold else { return limited }
        let firstFour = limited.prefix(4)
        let rest = limited.dropFirst(4)
        return rest.isEmpty ? "\(firstFour)-" : "\(firstFour)-\(rest)"
    }
}
