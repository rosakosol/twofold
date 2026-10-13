//
//  SwipeChoiceCard.swift
//  Twofold
//
//  Tinder-style swipe card shared by This or That and Who's More Likely — the entire question is
//  one card; dragging past a threshold in either direction commits that side's answer and the
//  card flies off screen. Swipe-only, deliberately — an earlier version also accepted a tap on
//  either half via a second, separate gesture recognizer layered on top of this one, and having
//  two recognizers compete over the same touch was exactly what made swipes unreliable (most
//  visible on Simulator, where a trackpad-driven drag is more sensitive to this than a real
//  finger). One recognizer, one gesture.
//

import SwiftUI

/// The card's own fly-off animation duration — `fly(direction:action:)` holds off calling the
/// real action for exactly this long, so the round/content change it triggers upstream can't
/// swap the card out mid-flight (see that function's comment for why that mattered). A plain
/// top-level constant, not `static` on `SwipeChoiceCard` itself, since Swift doesn't allow
/// static stored properties on a generic type.
private let swipeCardFlyDuration: Double = 0.3

struct SwipeChoiceCard<Content: View>: View {
    let gameType: GameType
    let leftLabel: String
    let rightLabel: String
    var isDisabled: Bool = false
    @ViewBuilder var content: Content
    let onChooseLeft: () -> Void
    let onChooseRight: () -> Void

    /// Where the finger has the card, for as long as a drag is in progress.
    ///
    /// `@GestureState`, because SwiftUI puts it back to zero itself when the gesture ends *or is
    /// cancelled*, and animates it back with the transaction below. That is the whole fix for cards
    /// left stuck part-way across the screen.
    ///
    /// The card's position used to be plain `@State`, written by `onChanged` and put back only by
    /// our own code: `onEnded`, and later a safety net watching a separate `@GestureState` flag
    /// for drags the system cancelled (the back-swipe claiming a touch near the left edge, a
    /// notification pulled down, a call). Both depended on SwiftUI reporting that the drag had
    /// stopped, and a report from a real device, a half swipe left frozen past the threshold with
    /// the stamp showing, says some path still didn't. Now nothing has to report it: the position
    /// *is* the gesture's state, so when the gesture goes, so does the offset.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8)))
    private var dragOffset: CGSize = .zero
    /// Set only once a swipe commits, to fly the card off. Takes over from `dragOffset`, which is
    /// about to reset to zero underneath it.
    @State private var flyOffset: CGSize?
    /// True the instant a swipe commits — separate from `isDisabled` (which the caller controls)
    /// because this needs to latch immediately to block a second drag on the same card while
    /// it's still flying off-screen, before the caller's own state even has a chance to update.
    @State private var hasCommitted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let threshold: CGFloat = 110

    private var offset: CGSize { flyOffset ?? dragOffset }

    /// The game's own colour (section 2.5), the same in both appearances: a game's colour follows
    /// it from its tile to this card to its results.
    private var cardGradient: LinearGradient { gameType.gradient }

    private var leftStampOpacity: Double { Double(max(0, min(1, -offset.width / threshold))) }
    private var rightStampOpacity: Double { Double(max(0, min(1, offset.width / threshold))) }

    var body: some View {
        ZStack {
            ghostCard(scale: 0.93, yOffset: 18, opacity: 0.35)
            ghostCard(scale: 0.965, yOffset: 9, opacity: 0.6)

            content
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(Theme.Spacing.lg)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(cardGradient)
                        .overlay { BrandHighlight() }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(.white)
                        .opacity(0.16 * max(leftStampOpacity, rightStampOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(.white, lineWidth: 3)
                        .opacity(max(leftStampOpacity, rightStampOpacity) >= 1 ? 1 : 0)
                }
                .overlay(alignment: .topLeading) { stamp(leftLabel).opacity(leftStampOpacity) }
                .overlay(alignment: .topTrailing) { stamp(rightLabel).opacity(rightStampOpacity) }
                // Small brand mark, always present — the drag stamp sharing this corner is
                // opacity-0 except mid-swipe, so this is the only thing here the rest of the
                // time.
                .overlay(alignment: .topTrailing) { brandMark }
                .shadow(color: Theme.Shadow.color, radius: 20, y: 14)
                // The tilt is a flourish on top of the drag, so Reduce Motion drops it; the card
                // still follows the finger, which is the gesture itself.
                .rotationEffect(.degrees(reduceMotion ? 0 : offset.width / 18))
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .updating($dragOffset) { value, state, _ in
                            guard !isDisabled, !hasCommitted else { return }
                            state = value.translation
                        }
                        .onEnded { value in
                            // Nothing to do for a swipe that didn't reach the threshold: the card's
                            // drag position resets by itself (see `dragOffset`).
                            guard !isDisabled, !hasCommitted else { return }
                            if value.translation.width <= -threshold {
                                fly(direction: -1, from: value.translation, action: onChooseLeft)
                            } else if value.translation.width >= threshold {
                                fly(direction: 1, from: value.translation, action: onChooseRight)
                            }
                        }
                )
                // A VoiceOver-driven action runs through the accessibility tree, not a second
                // UIKit gesture recognizer — unlike the tap-fallback approach this file's own
                // header comment explains was removed for conflicting with the drag gesture,
                // this can't compete with it. `.combine` reads the question content (from
                // `content`) as one phrase; the two actions are reachable via VoiceOver's
                // actions rotor as a swipe-free way to answer.
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text(leftLabel)) {
                    guard !isDisabled, !hasCommitted else { return }
                    fly(direction: -1, from: .zero, action: onChooseLeft)
                }
                .accessibilityAction(named: Text(rightLabel)) {
                    guard !isDisabled, !hasCommitted else { return }
                    fly(direction: 1, from: .zero, action: onChooseRight)
                }
        }
    }

    /// A static, slightly smaller/lower/fainter card peeking out from behind the real one — the
    /// classic "deck of cards" cue that there's more than one question, without actually needing
    /// to pre-render the next round's content. Same gradient as the front card (just faded via
    /// `opacity`) so the stack reads as one cohesive set of cards, not a colored card in front of
    /// plain white ones.
    private func ghostCard(scale: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(cardGradient)
            .frame(maxWidth: .infinity, minHeight: 240)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(opacity)
    }

    /// Animates the card fully off-screen *before* calling `action` — `action` is what ultimately
    /// changes which round is showing upstream (submitting an answer advances to the next one),
    /// and that swap was cutting this animation off almost immediately after it started (the
    /// underlying round view gets a fresh `.id()` the instant the new round becomes current,
    /// tearing this whole view down mid-flight). Deferring `action` until the fly-off has had
    /// time to actually play is what makes the swipe read as "the card flew away" instead of a
    /// glitchy flash.
    private func fly(direction: CGFloat, from start: CGSize, action: @escaping () -> Void) {
        hasCommitted = true
        // Pinned where the finger left it before anything else, so the card takes over from the
        // drag at the same spot instead of following `dragOffset` back towards the middle.
        flyOffset = start
        guard !reduceMotion else {
            // No animation to wait out, so no reason to defer the actual answer submission.
            action()
            return
        }
        withAnimation(.easeOut(duration: swipeCardFlyDuration)) {
            flyOffset = CGSize(width: direction * 600, height: start.height)
        }
        Task {
            try? await Task.sleep(for: .seconds(swipeCardFlyDuration))
            action()
        }
    }

    private func stamp(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.heavy))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            .rotationEffect(.degrees(-12))
            .padding(Theme.Spacing.md)
    }

    private var brandMark: some View {
        HStack(spacing: 4) {
            Image("GlobeHeart")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
            // Same serif wordmark treatment as WelcomeView's sign-in screen (just much smaller
            // here — that one is size 56 for a full-screen splash).
            Text("twofold")
                .font(.newsreader(size: 13))
                .foregroundStyle(Theme.onFill)
        }
        // Matches the content's own inset from the card edge (see `content.padding(Theme.Spacing.lg)`
        // above) so this sits at the same distance from the corner as the "1/8" round counter
        // does from the top edge, instead of hugging the corner more tightly than it does.
        .padding(Theme.Spacing.lg)
    }
}
