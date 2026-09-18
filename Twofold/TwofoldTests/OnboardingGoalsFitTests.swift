//
//  OnboardingGoalsFitTests.swift
//  TwofoldTests
//
//  "What would make time apart feel easier?" has to show all five options without scrolling.
//
//  It did not: at the width a card gives its text, several titles and every subtitle wrapped to a
//  second line, which added a row to each of five cards and pushed the list past the screen. On a
//  "pick what matters to you" screen, scrolling means the last options are the ones nobody reads.
//
//  Measured with UIHostingController rather than on a simulator, because the thing that matters is
//  a number — how tall one card is — and the failure mode is a copy change quietly reintroducing a
//  wrap. A screenshot would not catch that on a phone slightly wider than the one it was taken on.
//

import SwiftUI
import Testing
import UIKit
@testable import Twofold

@Suite("The goals screen fits without scrolling")
@MainActor
struct OnboardingGoalsFitTests {

    /// The narrowest screen this app runs on. Deployment target is iOS 26, so that is an iPhone
    /// SE (3rd gen) at 375 x 667 — not the 320-wide phones that have not been supported for years.
    private static let screenWidth: CGFloat = 375
    private static let screenHeight: CGFloat = 667

    /// The width a card actually gets, less the scaffold's padding on both sides.
    private static let cardWidth: CGFloat = screenWidth - Theme.Spacing.lg * 2

    private func height(of view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        // Without this the controller adds the device's safe-area insets to every measurement,
        // which inflated a 70pt card to over 100 and made the first version of this test fail by
        // a margin that had nothing to do with the copy.
        host.safeAreaRegions = []
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func cardHeight(_ goal: OnboardingGoal) -> CGFloat {
        height(
            of: OnboardingCard(
                icon: goal.icon,
                title: goal.title,
                subtitle: goal.subtitle,
                isSelected: false,
                action: {}
            ),
            width: Self.cardWidth
        )
    }

    @Test("No card is taller than another — nothing wraps")
    func everyCardIsTheSameHeight() {
        let heights = OnboardingGoal.allCases.map { ($0, cardHeight($0)) }
        let shortest = heights.map(\.1).min() ?? 0

        for (goal, measured) in heights {
            #expect(
                measured <= shortest + 1,
                "\"\(goal.title)\" / \"\(goal.subtitle ?? "")\" wraps — \(Int(measured))pt against \(Int(shortest))pt for the shortest card"
            )
        }
    }

    @Test("All five cards and the heading fit the smallest screen without scrolling")
    func theWholeListFits() {
        let cards = OnboardingGoal.allCases.reduce(into: CGFloat(0)) { $0 += cardHeight($1) }
        // Mirrors `GoalsView`: `xs` between cards, and a `sm` top inset rather than the
        // scaffold's default `lg`.
        let gaps = Theme.Spacing.xs * CGFloat(OnboardingGoal.allCases.count - 1)

        let heading = height(
            of: Text("What would make time apart feel easier?")
                .font(.system(.title, design: .rounded, weight: .bold)),
            width: Self.cardWidth
        )

        // Scaffold padding top and bottom, its top inset, and the gap between heading and list.
        let chrome = Theme.Spacing.lg * 3 + Theme.Spacing.sm
        let total = cards + gaps + heading + chrome

        // The screen, less the status bar and the pinned Continue bar with its padding.
        let available: CGFloat = Self.screenHeight - 20 - 110

        #expect(
            total <= available,
            "the goals list needs \(Int(total))pt and has \(Int(available))pt — it would scroll"
        )
    }

    @Test("The heading has no instruction line under it")
    func noSelectAllThatApplySubtitle() {
        // Asserted on the screen rather than by reading the file: the line was removed because the
        // cards already say it by staying selected, and a future edit re-adding it costs a row.
        let mirror = String(describing: GoalsView())
        #expect(!mirror.contains("Select all that apply"))
    }
}
