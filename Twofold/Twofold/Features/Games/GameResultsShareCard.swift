//
//  GameResultsShareCard.swift
//  Twofold
//
//  Genuinely different layouts (not just recolored variants of one fixed body) — see
//  `GameResultShareLayout`. Each owns its own visual identity so swiping through them in
//  `GameResultsShareView` reads as distinct cards/stickers, not one card with a palette swap.
//
//  Colors come from `ShareCardPalette` (the dark-mode/Daylight handoff's own sky/leaf/heart
//  canvas system for exportable cards) rather than the app's `Theme.*` tokens — this card is an
//  image that leaves the app, so it needs its own dark-canvas/light-pastel look regardless of
//  in-app chrome, the same way `ShareCard.dc.html`'s Quote/Chat/Score/Tally layouts do.
//

import SwiftUI

struct GameResultsShareCard: View {
    let data: GameResultShareData
    let layout: GameResultShareLayout
    /// Chosen on the share screen rather than fixed per layout.
    ///
    /// Each layout used to hardcode its own accent — score snapshot tinted by the match result,
    /// speech bubble always pink, and so on — which meant a game type with a single layout had a
    /// single colour and no say in it. Every game type offers all three now; `defaultAccent` keeps
    /// the old per-result tint as the *starting* choice rather than the only one.
    var accent: ShareCardAccent

    @Environment(\.colorScheme) private var colorScheme

    private func palette(_ accent: ShareCardAccent) -> ShareCardPalette {
        .resolve(accent, for: colorScheme)
    }

    var body: some View {
        Group {
            switch layout {
            case .scoreSnapshot: scoreSnapshotBody
            case .dailyStreak: dailyStreakBody
            case .namesAndAnswer: namesAndAnswerBody
            case .speechBubble: speechBubbleBody
            }
        }
        // Pinned, because this renders to a fixed-size image that leaves the device: it should
        // look the same to whoever receives it rather than reflowing to the sender's text size.
        .dynamicTypeSize(.large)
    }

    private func canvasBackground(_ palette: ShareCardPalette) -> some View {
        ZStack {
            palette.canvasGradient
            palette.glowOverlay
        }
    }

    // MARK: - Score snapshot

    /// Where the colour picker starts: tinted by the actual result for the match games (matching
    /// `GameResultsView.similarityTint`), falling back to `.sky` for Trivia and the Daily Question,
    /// which have no single "how well did we do" colour to react to.
    static func defaultAccent(for data: GameResultShareData) -> ShareCardAccent {
        guard let matchPercent = data.matchPercent else { return .sky }
        switch matchPercent {
        case 80...: return .leaf
        case 50..<80: return .sky
        default: return .heart
        }
    }

    private var scoreSnapshotBody: some View {
        let palette = palette(accent)
        return cardChrome(background: canvasBackground(palette), textColor: palette.foreground, brandMark: .top) {
            VStack(spacing: 4) {
                Image(systemName: data.gameType.icon)
                    .font(.caption)
                    .foregroundStyle(palette.foreground.opacity(0.8))
                Text(data.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(palette.foreground.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            scoreHeadline(palette)

            HStack(spacing: Theme.Spacing.md) {
                AvatarView(person: data.me, size: 40, showsRing: true)
                AvatarView(person: data.partner, size: 40, showsRing: true)
            }
        }
    }

    @ViewBuilder
    private func scoreHeadline(_ palette: ShareCardPalette) -> some View {
        if let matchPercent = data.matchPercent {
            VStack(spacing: 2) {
                Text("\(matchPercent)%")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.foreground)
                Text("answer similarity")
                    .font(.subheadline)
                    .foregroundStyle(palette.foreground.opacity(0.85))
            }
        } else if let myScore = data.triviaMyScore, let partnerScore = data.triviaPartnerScore, let total = data.triviaTotalRounds {
            HStack(spacing: Theme.Spacing.xl) {
                scoreColumn(value: "\(myScore)", label: data.me.name, palette: palette)
                Text("/\(total)")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.foreground.opacity(0.7))
                scoreColumn(value: "\(partnerScore)", label: data.partner.name, palette: palette)
            }
        }
    }

    private func scoreColumn(value: String, label: String, palette: ShareCardPalette) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(palette.foreground)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(palette.foreground.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Daily streak

    private var dailyStreakBody: some View {
        let palette = palette(accent)
        return cardChrome(background: canvasBackground(palette), textColor: palette.foreground, brandMark: .top) {
            Text(data.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(palette.foreground.opacity(0.8))

            if let question = data.singleRoundQuestion {
                Text(question)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(palette.foreground.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.sm) {
                messageBubble(name: data.me.name, text: data.myAnswer, alignment: .leading, palette: palette, isMine: true)
                messageBubble(name: data.partner.name, text: data.partnerAnswer, alignment: .trailing, palette: palette, isMine: false)
            }
        }
    }

    /// A little chat-style exchange — mine on the left, partner's underneath on the right — rather
    /// than two stacked left-aligned lines, so the two answers read as a back-and-forth. Mine is
    /// the accent-filled bubble, partner's a neutral surface — the same "Player A bubble = accent
    /// fill" rule the handoff's Chat card uses.
    private func messageBubble(name: String, text: String?, alignment: HorizontalAlignment, palette: ShareCardPalette, isMine: Bool) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(name.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(palette.foreground.opacity(0.75))
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
                .foregroundStyle(isMine ? palette.bubbleForeground : palette.foreground)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 210, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isMine ? AnyShapeStyle(palette.fill) : AnyShapeStyle(palette.surface), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    if !isMine {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(palette.surfaceLine, lineWidth: 1)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: - Names & answer

    private var namesAndAnswerBody: some View {
        let palette = palette(accent)
        return cardChrome(background: canvasBackground(palette), textColor: palette.foreground, brandMark: .bottom) {
            Text(data.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(palette.foreground.opacity(0.72))

            if let question = data.singleRoundQuestion {
                Text(question)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(palette.foreground)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: Theme.Spacing.md) {
                plainAnswerLine(name: data.me.name, text: data.myAnswer, palette: palette)
                plainAnswerLine(name: data.partner.name, text: data.partnerAnswer, palette: palette)
            }
        }
    }

    private func plainAnswerLine(name: String, text: String?, palette: ShareCardPalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.foreground.opacity(0.72))
            Text(text?.isEmpty == false ? text! : "Skipped this one")
                .font(.subheadline)
                .foregroundStyle(palette.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(palette.surfaceLine, lineWidth: 1)
        }
    }

    // MARK: - Speech bubble

    /// Almost no chrome beyond a tiny brand mark and the question — the exchange itself (a real
    /// tailed chat bubble per side, unlike `messageBubble`'s plain rounded rectangle above) is
    /// meant to be the whole visual, not one element inside a bigger composed card.
    private var speechBubbleBody: some View {
        // Leaf, not sky. `namesAndAnswer` above already owns sky, and these two are offered
        // together every time — they're the whole set for a Deep Conversations deck, and two of
        // the three for the Daily Question. Sharing an accent meant swiping between them changed
        // only the arrangement of the text on an identical canvas, which reads as the same card
        // twice rather than a choice. Every accent is now used exactly once per game.
        let palette = palette(accent)
        return VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: palette.foreground, size: 20, textStyle: .subheadline)

            // Every other layout (score snapshot, daily streak, names & answer) shows
            // `data.title` — this one was the odd one out, showing only the brand mark and
            // question with no indication of which deck/game it came from.
            Text(data.title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(palette.foreground.opacity(0.72))

            if let question = data.singleRoundQuestion {
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.foreground.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            VStack(spacing: Theme.Spacing.md) {
                speechBubble(name: data.me.name, text: data.myAnswer, tailOnRight: false, palette: palette, isMine: true)
                speechBubble(name: data.partner.name, text: data.partnerAnswer, tailOnRight: true, palette: palette, isMine: false)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.vertical, Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(canvasBackground(palette))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func speechBubble(name: String, text: String?, tailOnRight: Bool, palette: ShareCardPalette, isMine: Bool) -> some View {
        HStack {
            if tailOnRight { Spacer(minLength: 32) }
            VStack(alignment: tailOnRight ? .trailing : .leading, spacing: 4) {
                Text(name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.foreground.opacity(0.72))
                Text(text?.isEmpty == false ? text! : "Skipped this one")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isMine ? palette.bubbleForeground : palette.foreground)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 220, alignment: .leading)
                    // `SpeechBubbleShape` carves its rounded body out of the *top* `height -
                    // tailHeight` (9pt) of whatever frame it's given, leaving the bottom 9pt for
                    // the tail triangle — so a uniform `.padding(.vertical, 18)` here looked
                    // visibly uneven: the full 18pt shows above the text, but only 18 - 9 = 9pt of
                    // it remains between the text and the body's rounded bottom edge (the rest is
                    // the tail cutout). Padding the bottom by the tail height on top of the
                    // baseline 18 (i.e. 18 + 9 = 27) makes the two edges match visually instead of
                    // just numerically.
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 18 + SpeechBubbleShape.defaultTailHeight)
                    .background(SpeechBubbleShape(tailOnRight: tailOnRight).fill(isMine ? AnyShapeStyle(palette.fill) : AnyShapeStyle(palette.surface)))
                    .overlay(SpeechBubbleShape(tailOnRight: tailOnRight).stroke(isMine ? Color.clear : palette.surfaceLine, lineWidth: 1))
            }
            if !tailOnRight { Spacer(minLength: 32) }
        }
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
        deepConversationRounds: nil,
        singleRoundQuestion: nil,
        myAnswer: nil,
        partnerAnswer: nil,
        dailyStreak: nil
    )
    return ScrollView {
        GameResultsShareCard(data: data, layout: .scoreSnapshot, accent: GameResultsShareCard.defaultAccent(for: data))
            .padding()
    }
    .background(Color.black)
}
