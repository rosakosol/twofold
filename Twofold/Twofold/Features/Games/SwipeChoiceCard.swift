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

/// Card background — deliberately the same sky-blue-to-leaf-green gradient Trivia Battle uses
/// (`GameType.triviaBattle.iconGradient`) so every game's cards read as one consistent family
/// rather than This or That/More Likely looking like a different, plainer app.
private let swipeCardGradient = LinearGradient(colors: [Theme.skyBlue, Theme.leafGreen], startPoint: .topLeading, endPoint: .bottomTrailing)

struct SwipeChoiceCard<Content: View>: View {
    let leftLabel: String
    let rightLabel: String
    var isDisabled: Bool = false
    @ViewBuilder var content: Content
    let onChooseLeft: () -> Void
    let onChooseRight: () -> Void

    @State private var offset: CGSize = .zero
    /// True the instant a swipe commits — separate from `isDisabled` (which the caller controls)
    /// because this needs to latch immediately to block a second drag on the same card while
    /// it's still flying off-screen, before the caller's own state even has a chance to update.
    @State private var hasCommitted = false

    private let threshold: CGFloat = 110

    private var leftStampOpacity: Double { Double(max(0, min(1, -offset.width / threshold))) }
    private var rightStampOpacity: Double { Double(max(0, min(1, offset.width / threshold))) }

    var body: some View {
        ZStack {
            ghostCard(scale: 0.93, yOffset: 18, opacity: 0.35)
            ghostCard(scale: 0.965, yOffset: 9, opacity: 0.6)

            content
                .frame(maxWidth: .infinity, minHeight: 240)
                .padding(Theme.Spacing.lg)
                .background(swipeCardGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
                .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                .rotationEffect(.degrees(offset.width / 18))
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isDisabled, !hasCommitted else { return }
                            offset = value.translation
                        }
                        .onEnded { value in
                            guard !isDisabled, !hasCommitted else { return }
                            if value.translation.width <= -threshold {
                                fly(direction: -1, action: onChooseLeft)
                            } else if value.translation.width >= threshold {
                                fly(direction: 1, action: onChooseRight)
                            } else {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    offset = .zero
                                }
                            }
                        }
                )
        }
    }

    /// A static, slightly smaller/lower/fainter card peeking out from behind the real one — the
    /// classic "deck of cards" cue that there's more than one question, without actually needing
    /// to pre-render the next round's content. Same gradient as the front card (just faded via
    /// `opacity`) so the stack reads as one cohesive set of cards, not a colored card in front of
    /// plain white ones.
    private func ghostCard(scale: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(swipeCardGradient)
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
    private func fly(direction: CGFloat, action: @escaping () -> Void) {
        hasCommitted = true
        withAnimation(.easeOut(duration: swipeCardFlyDuration)) {
            offset = CGSize(width: direction * 600, height: offset.height)
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
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
        }
        // Matches the content's own inset from the card edge (see `content.padding(Theme.Spacing.lg)`
        // above) so this sits at the same distance from the corner as the "1/8" round counter
        // does from the top edge, instead of hugging the corner more tightly than it does.
        .padding(Theme.Spacing.lg)
    }
}
