//
//  InviteCode.swift
//  Twofold
//
//  Stands in for a real backend-issued invite code/link. Resolving a code to an
//  inviter's name and validating acceptance would happen server-side once Twofold
//  has one; here a code is just a locally-generated string.
//

import Foundation

enum InviteCode {
    static func generate(firstName: String) -> String {
        let prefix = firstName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "TWOFOLD"
            : firstName.uppercased()
        let suffix = Int.random(in: 1000...9999)
        return "\(prefix)-\(suffix)"
    }

    /// Mocks resolving a code to the inviter's display name (a real backend would look this up).
    static func inviterName(from code: String) -> String {
        let prefix = code.split(separator: "-").first.map(String.init) ?? "your partner"
        return prefix.capitalized
    }

    static func shareURL(for code: String) -> URL {
        URL(string: "twofold://invite/\(code)")!
    }

    /// Parses `twofold://invite/<CODE>` deep links.
    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "twofold" else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        if url.host?.lowercased() == "invite", let code = components.first {
            return code.uppercased()
        }
        if let code = components.last, components.contains(where: { $0.lowercased() == "invite" }) {
            return code.uppercased()
        }
        return nil
    }
}
