//
//  PasswordStrength.swift
//  Twofold
//
//  The strength meter. The rule it draws lives in `Shared/PasswordPolicy.swift`, which is also what
//  the Continue buttons gate on and what the website ports — one rule, three readers.
//
//  The meter used to be the only feedback: a bar that said "Weak" while the button sat disabled,
//  leaving you to guess which unstated rule you had broken. It now shows the reason too, because a
//  refusal nobody can act on is the same dead end as no button at all.
//

import SwiftUI

extension PasswordStrength {
    var color: Color {
        switch self {
        case .weak: Theme.error
        // DESIGN: blue, not amber. Amber is reserved for delays, and "fair" is not a warning.
        case .fair: Theme.accent
        case .strong: Theme.success
        }
    }
}

/// A 3-segment strength bar + label + reason, shown once a password field is non-empty — same
/// "live feedback while typing" spirit as the "Passwords don't match" caption these screens
/// already show.
///
/// `name` and `email` are passed so the meter judges the password the same way the button does:
/// without them it would rate somebody's own name as fair and the button would still refuse it.
struct PasswordStrengthView: View {
    let password: String
    var name: String?
    var email: String?

    private var strength: PasswordStrength { PasswordPolicy.evaluate(password, name: name, email: email) }
    private var reason: String? { PasswordPolicy.rejectionReason(password, name: name, email: email) }

    var body: some View {
        if !password.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            Capsule()
                                .fill(index <= strength.rawValue ? strength.color : Theme.textSecondary.opacity(0.2))
                                .frame(height: 4)
                        }
                    }
                    Text(strength.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(strength.color)
                }

                if let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
