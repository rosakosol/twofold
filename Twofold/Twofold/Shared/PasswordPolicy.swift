//
//  PasswordPolicy.swift
//  Twofold
//
//  What counts as an acceptable password, and how strong it is.
//
//  The rule this replaces was a length test wearing a variety test's clothes. Its tiers read:
//
//      if length >= 12 && variety >= 3 { return .strong }
//      if length >= 10 && variety >= 2 { return .strong }
//      if length >= 8  && variety >= 2 { return .fair }
//      if length >= 8                  { return .fair }   // <- this one
//      return .weak
//
//  Every screen gates on `> .weak`, so that fourth line meant eight characters of anything passed:
//  "password", "12345678", "aaaaaaaa", the user's own first name padded out. The variety count above
//  it never decided an outcome it could not already reach on length alone, and the separate
//  `password.count >= 6` check at each call site could never fail.
//
//  ---------------------------------------------------------------------------
//  What it does now
//  ---------------------------------------------------------------------------
//
//  Rejected outright:
//    - shorter than 10
//    - missing a capital, a lowercase letter, a number or a special character
//    - a known common password, with trailing digits and symbols ignored so "Password1!" is not a
//      new idea — which matters more here than anywhere, because a composition rule's most
//      predictable output is exactly that password
//    - one short string repeated to length — "passwordpassword" clears sixteen characters and a
//      whole-string blocklist at once, which is the trick a length floor invites
//    - four or more identical characters in a row, or four or more running in sequence
//    - anything containing the person's own name or email address
//
//  All four character classes are required at every length. That is a product decision rather than
//  the cryptographic optimum: NIST 800-63B advises against composition mandates, because they reject
//  "correcthorsebatterystaple" — twenty-five characters, one class, stronger than most of what this
//  rule admits — while nudging people towards "Password1!" and a sticky note.
//
//  The blocklist is what stops the second half of that from being a real hole. The stem check strips
//  trailing digits *and* symbols, so the obvious ways to make a banned password satisfy the classes
//  ("password1", "Password1!", "Qwerty12!") are all still refused.
//
//  ---------------------------------------------------------------------------
//  Kept in step with the website
//  ---------------------------------------------------------------------------
//
//  site/src/lib/marketing/passwordStrength.ts is a port of this file, because /pricing creates
//  accounts too and a password this refuses must not be creatable there. The two lists below and
//  the thresholds are the parts that have to match; they are duplicated by hand, the same way this
//  repo already accepts for FlightStatus and the support categories.
//

import Foundation

enum PasswordStrength: Int, Comparable {
    case weak, fair, strong

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .weak: "Weak"
        case .fair: "Fair"
        case .strong: "Strong"
        }
    }
}

enum PasswordPolicy {
    static let minLength = 10
    /// Where "fair" becomes "strong". Not a gate — everything below still has to pass every rule.
    static let strongLength = 14

    /// The passwords that turn up first in every credential-stuffing list. Compared after trailing
    /// digits are stripped, so "password123" and "letmein2024" are caught by their stems.
    ///
    /// Short by design. This is a speed bump against the handful of passwords that account for a
    /// wildly disproportionate share of compromised accounts, not a substitute for the breach
    /// corpus a server-side check would use — and it costs nothing at signup, which a network call
    /// would.
    private static let commonPasswords: Set<String> = [
        "password", "passw0rd", "pass", "qwerty", "qwertyuiop", "asdfgh", "zxcvbn",
        "iloveyou", "princess", "sunshine", "football", "baseball", "superman", "batman",
        "dragon", "monkey", "master", "shadow", "michael", "jennifer", "jordan",
        "letmein", "welcome", "admin", "login", "abc", "trustno", "starwars",
        "whatever", "freedom", "hello", "charlie", "donald", "qazwsx", "soccer",
        "killer", "ninja", "mustang", "access", "flower", "hottie", "loveme",
        "zaq", "google", "chocolate", "computer", "internet", "samsung", "cheese",
        "twofold", "relationship", "boyfriend", "girlfriend", "longdistance",
    ]

    /// Whether the password is good enough to create or change an account with. The gate every
    /// screen actually uses — `evaluate` exists for the meter, this exists for the button.
    static func isAcceptable(_ password: String, name: String? = nil, email: String? = nil) -> Bool {
        evaluate(password, name: name, email: email) > .weak
    }

    /// Why it was refused, phrased for the person typing it. Nil when it passes.
    ///
    /// Separate from `evaluate` because a disabled button with no reason is its own dead end: the
    /// old screens showed a strength bar that said "Weak" and left you to guess which of four
    /// unstated rules you had broken.
    static func rejectionReason(_ password: String, name: String? = nil, email: String? = nil) -> String? {
        if password.count < minLength {
            return "Use at least \(minLength) characters."
        }
        if containsPersonalInformation(password, name: name, email: email) {
            return "Don't use your name or email address in your password."
        }
        if isCommon(password) {
            return "That's a commonly used password — please pick something less guessable."
        }
        if let unit = repeatedUnit(password), unit.count < 4 || isCommon(unit) {
            return "Repeating a word doesn't make it a stronger password."
        }
        if hasTrivialRun(password) {
            return "Avoid repeated or sequential characters like \"aaaa\" or \"1234\"."
        }
        if password.rangeOfCharacter(from: .uppercaseLetters) == nil {
            return "Add a capital letter."
        }
        if password.rangeOfCharacter(from: .lowercaseLetters) == nil {
            return "Add a lowercase letter."
        }
        if password.rangeOfCharacter(from: .decimalDigits) == nil {
            return "Add a number."
        }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil {
            return "Add a special character, like ! or ?"
        }
        return nil
    }

    static func evaluate(_ password: String, name: String? = nil, email: String? = nil) -> PasswordStrength {
        guard rejectionReason(password, name: name, email: email) == nil else { return .weak }
        // Everything reaching here already carries all four classes, so length is the only thing
        // left to distinguish on.
        return password.count >= strongLength ? .strong : .fair
    }

    // MARK: - Individual rules

    static func varietyCount(_ password: String) -> Int {
        var count = 0
        if password.rangeOfCharacter(from: .uppercaseLetters) != nil { count += 1 }
        if password.rangeOfCharacter(from: .lowercaseLetters) != nil { count += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil { count += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { count += 1 }
        return count
    }

    /// Trailing digits and symbols are stripped before the lookup, because "password1",
    /// "password2024" and "Password1!" are the same idea as "password" and appear in the same lists.
    ///
    /// The symbol half is load-bearing now that a capital, a number and a symbol are all required:
    /// the shortest route from a banned password to a compliant one is to bolt one of each onto the
    /// end, and this is what makes that route a dead end.
    static func isCommon(_ password: String) -> Bool {
        let lowered = password.lowercased()
        if commonPasswords.contains(lowered) { return true }
        let stem = String(lowered.reversed().drop(while: { !$0.isLetter }).reversed())
        return !stem.isEmpty && commonPasswords.contains(stem)
    }

    /// Four or more of the same character, or four or more running consecutively in either
    /// direction — "aaaa", "1234", "dcba". Applied to the whole password rather than requiring the
    /// entire thing to be a run, so "myaaaapassword" is caught too.
    static func hasTrivialRun(_ password: String) -> Bool {
        let scalars = Array(password.lowercased().unicodeScalars).map { Int($0.value) }
        guard scalars.count >= 4 else { return false }

        var repeatRun = 1
        var ascending = 1
        var descending = 1
        for index in 1..<scalars.count {
            let delta = scalars[index] - scalars[index - 1]
            repeatRun = delta == 0 ? repeatRun + 1 : 1
            ascending = delta == 1 ? ascending + 1 : 1
            descending = delta == -1 ? descending + 1 : 1
            if repeatRun >= 4 || ascending >= 4 || descending >= 4 { return true }
        }
        return false
    }

    /// The whole password is one shorter string repeated: "passwordpassword", "abcabcabc",
    /// "abababababab". Returns the repeated unit, or nil if there isn't one.
    ///
    /// Worth its own rule because repetition satisfies a length floor and a whole-string blocklist
    /// simultaneously, which is precisely what somebody does when told their password is too short.
    /// Checked against the blocklist and against a minimum unit length, rather than banned outright
    /// — "tangerinetangerine" is repetitive but not guessable, and refusing it would be the kind of
    /// rule that sends people to a sticky note.
    static func repeatedUnit(_ password: String) -> String? {
        let characters = Array(password)
        let length = characters.count
        guard length >= 4 else { return nil }

        for unit in 1...(length / 2) where length % unit == 0 {
            let candidate = Array(characters[0 ..< unit])
            var matches = true
            var index = unit
            while index < length {
                if Array(characters[index ..< index + unit]) != candidate {
                    matches = false
                    break
                }
                index += unit
            }
            if matches { return String(candidate) }
        }
        return nil
    }

    /// The password contains the person's own name, or the local part of their email address.
    ///
    /// Four characters minimum on the needle, so somebody called "Al" is not told their password
    /// contains their name every time it happens to contain those two letters.
    static func containsPersonalInformation(_ password: String, name: String?, email: String?) -> Bool {
        let haystack = fold(password)
        var needles: [String] = []
        if let name { needles.append(fold(name)) }
        if let email {
            let localPart = email.split(separator: "@").first.map(String.init) ?? email
            needles.append(fold(localPart))
        }
        return needles.contains { $0.count >= 4 && haystack.contains($0) }
    }

    private static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { !$0.isWhitespace }
    }
}
