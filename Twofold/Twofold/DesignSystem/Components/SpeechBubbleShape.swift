//
//  SpeechBubbleShape.swift
//  Twofold
//
//  A real tailed chat-bubble outline (rounded rect + a small triangular tail cut into its own
//  bottom corner) — unlike `GameResultsShareCard`'s older `messageBubble`, which was a plain
//  `RoundedRectangle` with no tail. Built as a `Shape` (not a fixed view) so it works equally as
//  a `.fill()` background and a `.stroke()` border on any content size.
//

import SwiftUI

struct SpeechBubbleShape: Shape {
    var cornerRadius: CGFloat = 18
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 9
    /// true = tail at the bottom-right corner (an "outgoing"/your-side bubble), false =
    /// bottom-left (an "incoming"/their-side bubble) — same left/right convention iMessage uses.
    var tailOnRight: Bool

    func path(in rect: CGRect) -> Path {
        let bodyRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0, rect.height - tailHeight))
        var path = Path(roundedRect: bodyRect, cornerRadius: min(cornerRadius, bodyRect.height / 2))

        let baseY = bodyRect.maxY
        let tipY = rect.maxY
        if tailOnRight {
            let baseX = bodyRect.maxX - cornerRadius - tailWidth / 2
            path.move(to: CGPoint(x: baseX, y: baseY))
            path.addLine(to: CGPoint(x: baseX + tailWidth, y: baseY))
            path.addLine(to: CGPoint(x: baseX + tailWidth * 0.65, y: tipY))
            path.closeSubpath()
        } else {
            let baseX = bodyRect.minX + cornerRadius
            path.move(to: CGPoint(x: baseX, y: baseY))
            path.addLine(to: CGPoint(x: baseX + tailWidth, y: baseY))
            path.addLine(to: CGPoint(x: baseX + tailWidth * 0.35, y: tipY))
            path.closeSubpath()
        }
        return path
    }
}

#Preview {
    VStack(spacing: 16) {
        Text("Hey! What time works?")
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(SpeechBubbleShape(tailOnRight: false).fill(Color(.systemGray5)))
        Text("Anytime after 6 🎉")
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(SpeechBubbleShape(tailOnRight: true).fill(.blue))
    }
    .padding()
}
