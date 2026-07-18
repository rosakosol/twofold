//
//  GameResultsShareCard.swift
//  Twofold
//
//  Three genuinely different layouts (not just recolored variants of one fixed body) — see
//  `GameResultShareLayout`. Each owns its own visual identity so the picker in
//  `GameResultsShareView` reads as three distinct cards, not one card with a palette swap.
//

import SwiftUI

struct GameResultsShareCard: View {
    let data: GameResultShareData
    let layout: GameResultShareLayout

    var body: some View {
        switch layout {
        case .scoreSnapshot: scoreSnapshotBody
        case .dailyStreak: dailyStreakBody
        case .namesAndAnswer: namesAndAnswerBody
        }
    }

    // MARK: - Score snapshot

    private var scoreSnapshotBody: some View {
        cardChrome(background: scoreGradient, textColor: .white, brandMark: .top) {
            VStack(spacing: 4) {
                Image(systemName: data.gameType.icon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Text(data.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            scoreHeadline

            HStack(spacing: Theme.Spacing.md) {
                AvatarView(person: data.me, size: 40, showsRing: true)
                AvatarView(person: data.partner, size: 40, showsRing: true)
            }
        }
    }

    @ViewBuilder
    private var scoreHeadline: some View {
        if let matchPercent = data.matchPercent {
            VStack(spacing: 2) {
                Text("\(matchPercent)%")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("answer similarity")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        } else if let myScore = data.triviaMyScore, let partnerScore = data.triviaPartnerScore, let total = data.triviaTotalRounds {
            HStack(spacing: Theme.Spacing.xl) {
                scoreColumn(value: "\(myScore)", label: "You")
                Text("/\(total)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                scoreColumn(value: "\(partnerScore)", label: data.partner.name)
            }
        } else if let summary = data.deepConversationSummary {
            Text(summary)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
    }

    private func scoreColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    /// Tinted by the actual result for the match games (matches `GameResultsView.similarityTint`);
    /// falls back to the game type's own brand gradient for Trivia/Deep Conversations, which have
    /// no single "how well did we do" color to react to.
    private var scoreGradient: LinearGradient {
        if let matchPercent = data.matchPercent {
            let tint: Color = switch matchPercent {
            case 80...: Theme.leafGreen
            case 50..<80: Theme.skyBlue
            default: Theme.heartRed
            }
            return LinearGradient(colors: [tint, tint.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: data.gameType.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Daily streak

    private var dailyStreakGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: "FF9A56"), Color(hex: "E84C3D")], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var dailyStreakBody: some View {
        cardChrome(background: dailyStreakGradient, textColor: .white, brandMark: .top) {
            Text(data.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: Theme.Spacing.md) {
                AvatarView(person: data.me, size: 56, showsRing: true)
                AvatarView(person: data.partner, size: 56, showsRing: true)
            }

            if let streak = data.dailyStreak {
                HStack(spacing: 4) {
                    Text("🔥").font(.title3)
                    Text("\(streak)-day streak")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
            }

            if let question = data.singleRoundQuestion {
                Text(question)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.sm) {
                messageBubble(name: "You", text: data.myAnswer, alignment: .leading)
                messageBubble(name: data.partner.name, text: data.partnerAnswer, alignment: .trailing)
            }
        }
    }

    /// A little chat-style exchange — mine on the left, partner's underneath on the right — rather
    /// than two stacked left-aligned lines, so the two answers read as a back-and-forth.
    private func messageBubble(name: String, text: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.75))
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 210, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: - Names & answer

    private var namesAndAnswerBody: some View {
        cardChrome(background: LinearGradient(colors: [.white, Color(hex: "F4F4F4")], startPoint: .top, endPoint: .bottom), textColor: Theme.ink, brandMark: .bottom) {
            Text(data.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.subtleInk)

            if let question = data.singleRoundQuestion {
                Text(question)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.md) {
                plainAnswerLine(name: data.me.name, text: data.myAnswer)
                plainAnswerLine(name: data.partner.name, text: data.partnerAnswer)
            }
        }
    }

    private func plainAnswerLine(name: String, text: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared chrome

    private enum BrandMarkPlacement { case top, bottom }

    private func cardChrome<Background: View, Content: View>(
        background: Background,
        textColor: Color,
        brandMark: BrandMarkPlacement,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            if brandMark == .top {
                TwofoldBrandMark(color: textColor, size: 24, textStyle: .title3)
            }
            content()
            if brandMark == .bottom {
                TwofoldBrandMark(color: textColor, size: 20, textStyle: .subheadline)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }
}

#Preview {
    let data = GameResultShareData(
        gameType: .thisOrThat,
        title: "This or That",
        isDaily: false,
        me: MockData.dara,
        partner: MockData.rosa,
        matchPercent: 82,
        triviaMyScore: nil,
        triviaPartnerScore: nil,
        triviaTotalRounds: nil,
        deepConversationSummary: nil,
        singleRoundQuestion: nil,
        myAnswer: nil,
        partnerAnswer: nil,
        dailyStreak: nil
    )
    return ScrollView {
        GameResultsShareCard(data: data, layout: .scoreSnapshot)
            .padding()
    }
    .background(Color.black)
}
