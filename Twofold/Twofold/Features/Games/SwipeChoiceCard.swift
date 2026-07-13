//
//  SwipeChoiceCard.swift
//  Twofold
//
//  Tinder-style swipe card shared by This or That and Who's More Likely — the entire question is
//  one card; dragging past a threshold in either direction commits that side's answer and the
//  card flies off screen, rather than tapping one of two separate option buttons. A tap on either
//  half of the card is a lower-effort equivalent to a full swipe, for anyone who'd rather tap.
//

import SwiftUI

struct SwipeChoiceCard<Content: View>: View {
    let leftLabel: String
    let leftColor: Color
    let rightLabel: String
    let rightColor: Color
    var isDisabled: Bool = false
    @ViewBuilder var content: Content
    let onChooseLeft: () -> Void
    let onChooseRight: () -> Void

    @State private var offset: CGSize = .zero

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
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(offset.width < 0 ? leftColor : rightColor)
                        .opacity(0.12 * max(leftStampOpacity, rightStampOpacity))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(offset.width < 0 ? leftColor : rightColor, lineWidth: 3)
                        .opacity(max(leftStampOpacity, rightStampOpacity) >= 1 ? 1 : 0)
                }
                .overlay(alignment: .topLeading) { stamp(leftLabel, color: leftColor).opacity(leftStampOpacity) }
                .overlay(alignment: .topTrailing) { stamp(rightLabel, color: rightColor).opacity(rightStampOpacity) }
                .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                .rotationEffect(.degrees(offset.width / 18))
                .offset(offset)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isDisabled else { return }
                            offset = value.translation
                        }
                        .onEnded { value in
                            guard !isDisabled else { return }
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
                .overlay(tapHalves)
        }
    }

    /// A static, slightly smaller/lower/fainter card peeking out from behind the real one — the
    /// classic "deck of cards" cue that there's more than one question, without actually needing
    /// to pre-render the next round's content.
    private func ghostCard(scale: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(Theme.cardBackground)
            .frame(maxWidth: .infinity, minHeight: 240)
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .scaleEffect(scale)
            .offset(y: yOffset)
            .opacity(opacity)
    }

    /// Left/right invisible tap targets layered over the card — a tap-to-choose fallback for
    /// anyone who'd rather not drag.
    private var tapHalves: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle()).onTapGesture { guard !isDisabled else { return }; fly(direction: -1, action: onChooseLeft) }
            Color.clear.contentShape(Rectangle()).onTapGesture { guard !isDisabled else { return }; fly(direction: 1, action: onChooseRight) }
        }
    }

    private func fly(direction: CGFloat, action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.3)) {
            offset = CGSize(width: direction * 600, height: offset.height)
        }
        action()
    }

    private func stamp(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.heavy))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(color, lineWidth: 2))
            .rotationEffect(.degrees(-12))
            .padding(Theme.Spacing.md)
    }
}
