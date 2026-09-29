//
//  PasswordPolicyTests.swift
//  TwofoldTests
//
//  The rule this replaced ended `if length >= 8 { return .fair }`, and every screen gates on
//  `> .weak` — so eight characters of anything was an acceptable password. Many of the cases below
//  are the passwords that used to pass.
//
//  The rule now also requires a capital, a lowercase letter, a number and a special character at
//  every length. That is a deliberate product choice against NIST 800-63B's advice, and it has a
//  known failure mode: the most predictable password a composition rule produces is "Password1!".
//  A good half of this suite exists to make sure that one, and its relatives, are still refused.
//

import Testing
@testable import Twofold

struct PasswordPolicyTests {

    // MARK: - What used to get through

    @Test("eight characters of anything is no longer a password", arguments: [
        "password", "12345678", "aaaaaaaa", "abcdefgh", "qwertyui",
    ])
    func theOldFloorIsGone(_ password: String) {
        #expect(!PasswordPolicy.isAcceptable(password))
    }

    /// The composition rule's own worst output. Each of these satisfies every class and the length
    /// floor, and is refused anyway — by the stem check, which strips trailing digits *and* symbols.
    /// Without that, mandating a capital, a number and a symbol would have made these the passwords
    /// people actually chose.
    @Test("a banned password with a capital, a number and a symbol bolted on is still banned", arguments: [
        "Password1!", "Password123!", "Qwerty12!", "Iloveyou1!", "Letmein99!", "Monkey123!",
    ])
    func compositionCannotRescueACommonPassword(_ password: String) {
        #expect(!PasswordPolicy.isAcceptable(password))
    }

    /// The one that matters most here: people reach for their own name first, and the signup form
    /// is holding it while they type.
    @Test("a password containing the person's own name is refused")
    func ownNameIsRefused() {
        #expect(!PasswordPolicy.isAcceptable("Rosakosol2024!", name: "Rosa", email: "rosa@example.com"))
        #expect(!PasswordPolicy.isAcceptable("MyRosa-XYZ123", name: "Rosa", email: "x@example.com"))
    }

    @Test("a password containing the email's local part is refused")
    func emailIsRefused() {
        #expect(!PasswordPolicy.isAcceptable("Kosolrosa-9912", email: "kosolrosa@gmail.com"))
    }

    /// Two-letter names would otherwise flag almost everything, so the needle has a floor.
    @Test("a very short name is not treated as a password ingredient")
    func shortNamesDoNotFalselyMatch() {
        #expect(PasswordPolicy.isAcceptable("Planetary-Drift7", name: "Al", email: "al@example.com"))
    }

    @Test("runs and repeats are refused wherever they sit", arguments: [
        "MyAaaa-Passphrase1", "Hello1234-World!", "Zyxwvu-Secret1!",
    ])
    func trivialRunsAreRefused(_ password: String) {
        #expect(!PasswordPolicy.isAcceptable(password))
    }

    /// Doubling a banned password satisfies a length floor and a whole-string blocklist at once.
    @Test("a repeated password is still that password", arguments: [
        "passwordpassword", "qwertyqwerty", "abcabcabcabc", "abababababab",
    ])
    func repetitionIsNotLength(_ password: String) {
        #expect(!PasswordPolicy.isAcceptable(password))
    }

    // MARK: - The four classes

    @Test("each missing class is refused, and named", arguments: [
        ("lowercase7-only", "capital"),
        ("UPPERCASE7-ONLY", "lowercase"),
        ("NoDigitsHere-x!", "number"),
        ("NoSymbolsHere77", "special"),
    ])
    func eachClassIsRequired(_ password: String, _ expectedWord: String) {
        #expect(!PasswordPolicy.isAcceptable(password))
        #expect(PasswordPolicy.rejectionReason(password)?.lowercased().contains(expectedWord) == true)
    }

    /// The cost of the composition rule, recorded rather than hidden: this is twenty-five characters
    /// and far stronger than most of what the rule admits, and it is refused. If the requirement is
    /// ever revisited, this test is the argument.
    @Test("a long passphrase is refused for want of a capital, a number and a symbol")
    func passphrasesAreRefusedUnderThisPolicy() {
        #expect(!PasswordPolicy.isAcceptable("correcthorsebatterystaple"))
    }

    // MARK: - What should be allowed

    @Test("an ordinary password with all four classes passes", arguments: [
        "Tangerine7Moon!", "Brew-Coffee-42B", "Rivet9!Harbour",
    ])
    func ordinaryPasswordsPass(_ password: String) {
        #expect(PasswordPolicy.isAcceptable(password))
    }

    @Test("ten characters is the floor, and nine is not enough")
    func theFloorIsTen() {
        #expect(!PasswordPolicy.isAcceptable("Rivet9!Ha"))
        #expect(PasswordPolicy.isAcceptable("Rivet9!Har"))
    }

    /// Repetition alone is not the problem — a repeated unit that is neither short nor guessable is
    /// still fine, and refusing it would be the kind of rule people route around.
    @Test("a repeated ordinary word is not refused for repeating")
    func benignRepetitionPasses() {
        #expect(PasswordPolicy.isAcceptable("Tangerine1!Tangerine1!"))
    }

    @Test("length is what separates fair from strong")
    func strengthTiers() {
        #expect(PasswordPolicy.evaluate("Rivet9!Har") == .fair)
        #expect(PasswordPolicy.evaluate("Rivet9!Harbour") == .strong)
    }

    // MARK: - Saying why

    /// A disabled button with no reason is the dead end this replaced.
    @Test("every refused password comes with a reason", arguments: [
        "short", "password", "Aaaaaaaaaa1!", "lowercase7-only",
    ])
    func refusalsExplainThemselves(_ password: String) {
        #expect(PasswordPolicy.rejectionReason(password) != nil)
    }

    @Test("an accepted password has nothing to say")
    func acceptancesAreSilent() {
        #expect(PasswordPolicy.rejectionReason("Tangerine7Moon!") == nil)
    }

    /// Order matters, and this is where it shows. "password" is eight characters, so it is refused
    /// for length and never reaches the blocklist — the reason a person sees is the first rule they
    /// broke, not every rule they broke. The common-password message needs a password long enough to
    /// get that far.
    @Test("the reason names the rule that was broken")
    func reasonsAreSpecific() {
        #expect(PasswordPolicy.rejectionReason("Short1!")?.contains("10") == true)
        #expect(PasswordPolicy.rejectionReason("qwertyuiop")?.lowercased().contains("commonly") == true)
    }
}
