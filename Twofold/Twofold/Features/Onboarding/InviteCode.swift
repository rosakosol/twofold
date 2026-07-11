//
//  InviteCode.swift
//  Twofold
//
//  Sharing/parsing helpers for partner invite links. The actual code is always issued by the
//  backend (`create_invite_code` RPC) and validated on redeem (`redeem_invite_code` RPC) — this
//  type only builds/parses the URL around it.
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

    /// A locally-guessed display name from the code's prefix, shown before the real inviter's
    /// name is known (the backend doesn't return one on redeem) — e.g. "ROSA-4821" → "Rosa".
    static func inviterName(from code: String) -> String {
        let prefix = code.split(separator: "-").first.map(String.init) ?? "your partner"
        return prefix.capitalized
    }

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
}
