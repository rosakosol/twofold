//
//  LockScreenPhoneMock.swift
//  Twofold
//
//  Shared oversized-phone Lock Screen chassis — extracted from NotificationsSellView (the
//  original, only user of this mockup) so LiveActivitySellView can float its own content over
//  the identical chassis/Dynamic Island/clock instead of a bespoke background, matching the
//  visual language of a real iOS Lock Screen consistently across both sell screens.
//

import SwiftUI

struct LockScreenPhoneMock<Content: View>: View {
    let now: Date
    /// Positioned by the caller (e.g. `.padding(.top, ...)`) against the full mock's own
    /// coordinate space — the chassis/clock don't reserve space for it.
    @ViewBuilder var content: Content

    private static var clockFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }

    var body: some View {
        GeometryReader { geometry in
            let safeWidth = geometry.size.width.isFinite ? geometry.size.width : 340
            let phoneWidth = min(max(safeWidth - 60, 280), 390)

            ZStack(alignment: .top) {
                // Only the chassis + clock actually need truncating — they're 760pt tall against
                // a 500pt display window. Clipping *just* this group (instead of the whole
                // ZStack) keeps that crop vertical-only, so `content` below is free to bleed its
                // drop shadow past the left/right edges instead of having it hard-cut at the
                // container's exact width — the visible flat "wall" the un-clipped shadow used to
                // fade into before this was scoped down to only what needs clipping.
                Group {
                    RoundedRectangle(cornerRadius: 62, style: .continuous)
                        .fill(Color.black)
                        .overlay {
                            RoundedRectangle(cornerRadius: 62, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.17), lineWidth: 12)
                        }
                        .frame(width: phoneWidth, height: 760)
                        .zIndex(0)

                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: 82, height: 24)
                            .padding(.top, 32)

                        Text(Self.clockFormatter.string(from: now))
                            .font(.system(size: 86, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.top, 50)

                        Spacer(minLength: 0)
                    }
                    .frame(width: phoneWidth, height: 760)
                    .zIndex(1)
                }
                .frame(height: 500, alignment: .top)
                .clipped()

                content
                    .frame(width: geometry.size.width)
                    .zIndex(10)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(height: 500)
    }
}
