//
//  PasswordStrength.swift
//  Twofold
//
//  Shared client-side password strength check for every onboarding screen that creates a
//  password (CreateAccountView, SaveAccountView) — length plus character variety, not a strict
//  entropy calculation. Deliberately lenient (no forced symbol/uppercase requirement) so it steers
//  someone away from "123456" without turning into its own source of signup friction.
//

import SwiftUI

enum PasswordStrength: Int, Comparable {
    case weak
    case fair
    case strong

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func evaluate(_ password: String) -> PasswordStrength {
        let length = password.count
        var varietyCount = 0
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { varietyCount += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { varietyCount += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { varietyCount += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { varietyCount += 1 }

        if length >= 12 && varietyCount >= 3 { return .strong }
        if length >= 10 && varietyCount >= 2 { return .strong }
        if length >= 8 && varietyCount >= 2 { return .fair }
        if length >= 8 { return .fair }
        return .weak
    }

    var label: String {
        switch self {
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        }
    }

    var color: Color {
        switch self {
        case .weak: Theme.heartRed
        case .fair: .orange
        case .strong: Theme.leafGreen
        }
    }
}

/// A 3-segment strength bar + label, shown once a password field is non-empty — same "live
/// feedback while typing" spirit as the existing "Passwords don't match" caption these screens
/// already show.
struct PasswordStrengthView: View {
    let password: String

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }

    var body: some View {
        if !password.isEmpty {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= strength.rawValue ? strength.color : Theme.subtleInk.opacity(0.2))
                            .frame(height: 4)
                    }
                }
                Text(strength.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(strength.color)
            }
        }
    }
}
