//
//  InviteCodeParsingTests.swift
//  TwofoldTests
//
//  `InviteCode.code(from:)` decides whether a tapped link pairs you with somebody, and had no test
//  at all — the only references were its two call sites.
//
//  It also did not do what its own doc comment said. The legacy `twofold://invite/<CODE>` form was
//  unreachable: for that URL "invite" is the *host*, so `pathComponents` is ["/", "<CODE>"] and the
//  guard requiring "invite" among the components rejected it before the branch written to handle
//  it could run. Every legacy link shared before Universal Links existed has quietly done nothing.
//
//  And "contains the word invite, take the last component" was too loose in the other direction —
//  it read a code out of paths that were not invite links at all.
//

import Testing
import Foundation
@testable import Twofold

struct InviteCodeParsingTests {

    @Test("a universal link yields its code")
    func universalLink() {
        #expect(InviteCode.code(from: URL(string: "https://www.twofoldapp.com.au/invite/ABCDEFGH")!) == "ABCDEFGH")
    }

    @Test("codes are upper-cased, because that is how they are stored and compared")
    func lowercaseIsNormalised() {
        #expect(InviteCode.code(from: URL(string: "https://www.twofoldapp.com.au/invite/abcdefgh")!) == "ABCDEFGH")
    }

    /// The form the file promised backward compatibility for and never delivered.
    @Test("the legacy custom-scheme link works, which it did not before")
    func legacyCustomScheme() {
        #expect(InviteCode.code(from: URL(string: "twofold://invite/ABCDEFGH")!) == "ABCDEFGH")
    }

    // MARK: - What it must not accept

    /// `components.last` meant a trailing segment was read as a code whatever preceded it.
    @Test("a trailing segment after the code is not mistaken for one")
    func trailingSegmentIsRefused() {
        #expect(InviteCode.code(from: URL(string: "https://www.twofoldapp.com.au/invite/ABCD/EVIL")!) == nil)
    }

    /// This one shadowed widget routing: `RootView` tries the invite parser before
    /// `WidgetDeepLink`, so any `twofold://` path ending in /invite was consumed as the code
    /// "INVITE" rather than reaching the widget handler.
    @Test("a path merely ending in invite is not a code")
    func pathEndingInInviteIsRefused() {
        #expect(InviteCode.code(from: URL(string: "twofold://passport/invite")!) == nil)
    }

    @Test("another host's invite link is refused")
    func foreignHostIsRefused() {
        #expect(InviteCode.code(from: URL(string: "https://evil.example.com/invite/ABCDEFGH")!) == nil)
    }

    @Test("a link with no code is refused rather than returning an empty one")
    func missingCodeIsRefused() {
        #expect(InviteCode.code(from: URL(string: "https://www.twofoldapp.com.au/invite/")!) == nil)
        #expect(InviteCode.code(from: URL(string: "twofold://invite/")!) == nil)
    }

    @Test("an unrelated link is refused")
    func unrelatedLinkIsRefused() {
        #expect(InviteCode.code(from: URL(string: "https://www.twofoldapp.com.au/faq")!) == nil)
        #expect(InviteCode.code(from: URL(string: "twofold://memory/1234")!) == nil)
    }
}
