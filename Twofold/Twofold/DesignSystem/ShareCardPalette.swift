//
//  ShareCardPalette.swift
//  Twofold
//
//  Color source for exportable "share cards" (Game Results, Distance, Stats) — the images users
//  send to Instagram/Messages. Per the dark-mode/Daylight design handoff, these carry their own
//  canvas/accent palette rather than the app's own `Theme.*` tokens, because the card is a leaf
//  image that has to look right on its own (in Photos, in a Messages thread) instead of adapting
//  to in-app chrome. Values below are transcribed exactly from that handoff's `ShareCard.dc.html`
//  card-palette table — dark "Aurora" canvas + light "Daylight" pastel canvas, three accents
//  (sky/leaf/heart) each.
//

import SwiftUI

enum ShareCardAccent {
    case sky, leaf, heart
}

/// A fully-resolved set of colors for one accent, in one appearance. Every share card that draws
/// from this (not a raw hex) picks up both themes for free.
struct ShareCardPalette {
    let canvas: [Color]
    let glow: Color
    let accent: Color
    let chip: Color
    let chipLine: Color
    let fill: Color
    let bubbleForeground: Color

    let foreground: Color
    let surface: Color
    let surfaceLine: Color
    let track: Color
    let rule: Color
    let ringColor: Color
    let globeFill: Color
    let globeLine: Color

    static func resolve(_ accent: ShareCardAccent, dark: Bool) -> ShareCardPalette {
        let a = dark ? Self.darkAccents[accent]! : Self.lightAccents[accent]!
        return ShareCardPalette(
            canvas: a.canvas,
            glow: a.glow,
            accent: a.accent,
            chip: a.chip,
            chipLine: a.chipLine,
            fill: a.fill,
            bubbleForeground: a.bubbleForeground,
            foreground: dark ? Color(hex: "F4F9FC") : Color(hex: "16232F"),
            surface: dark ? Color.white.opacity(0.09) : Color.white.opacity(0.66),
            surfaceLine: dark ? Color.white.opacity(0.14) : Color(hex: "1C2A38").opacity(0.10),
            track: dark ? Color.white.opacity(0.16) : Color(hex: "1C2A38").opacity(0.14),
            rule: dark ? Color.white.opacity(0.12) : Color(hex: "1C2A38").opacity(0.12),
            ringColor: dark ? Color.white.opacity(0.9) : Color(hex: "1C2A38").opacity(0.22),
            globeFill: dark ? Color.white.opacity(0.05) : Color(hex: "1C2A38").opacity(0.07),
            globeLine: dark ? Color.white.opacity(0.22) : Color(hex: "1C2A38").opacity(0.20)
        )
    }

    static func resolve(_ accent: ShareCardAccent, for colorScheme: ColorScheme) -> ShareCardPalette {
        resolve(accent, dark: colorScheme == .dark)
    }

    private struct AccentColors {
        let canvas: [Color]
        let glow: Color
        let accent: Color
        let chip: Color
        let chipLine: Color
        let fill: Color
        let bubbleForeground: Color
    }

    private static let darkAccents: [ShareCardAccent: AccentColors] = [
        .sky: AccentColors(
            canvas: [Color(hex: "123045"), Color(hex: "0C2233"), Color(hex: "08161F")],
            glow: Color(hex: "4FA9E0").opacity(0.3),
            accent: Color(hex: "8ACFF5"),
            chip: Color(hex: "4FA9E0").opacity(0.22),
            chipLine: Color(hex: "8ACFF5").opacity(0.4),
            fill: Color(hex: "8ACFF5"),
            bubbleForeground: Color(hex: "08131C")
        ),
        .leaf: AccentColors(
            canvas: [Color(hex: "0F3229"), Color(hex: "0C2A2A"), Color(hex: "07171B")],
            glow: Color(hex: "6FBF8B").opacity(0.3),
            accent: Color(hex: "8FE3AE"),
            chip: Color(hex: "6FBF8B").opacity(0.22),
            chipLine: Color(hex: "8FE3AE").opacity(0.4),
            fill: Color(hex: "8FE3AE"),
            bubbleForeground: Color(hex: "08131C")
        ),
        .heart: AccentColors(
            canvas: [Color(hex: "331B26"), Color(hex: "2A1620"), Color(hex: "170D14")],
            glow: Color(hex: "E85C6B").opacity(0.28),
            accent: Color(hex: "FFA3AB"),
            chip: Color(hex: "E85C6B").opacity(0.22),
            chipLine: Color(hex: "FFA3AB").opacity(0.4),
            fill: Color(hex: "FFA3AB"),
            bubbleForeground: Color(hex: "1B0D12")
        ),
    ]

    private static let lightAccents: [ShareCardAccent: AccentColors] = [
        .sky: AccentColors(
            canvas: [Color(hex: "E4F2FC"), Color(hex: "D3E9F8"), Color(hex: "DFF2EC")],
            glow: Color(hex: "6EC1F0").opacity(0.4),
            accent: Color(hex: "1F6F9E"),
            chip: Color(hex: "4FA9E0").opacity(0.18),
            chipLine: Color(hex: "3D8FC9").opacity(0.34),
            fill: Color(hex: "2F82BE"),
            bubbleForeground: .white
        ),
        .leaf: AccentColors(
            canvas: [Color(hex: "E3F5EA"), Color(hex: "D6EFE2"), Color(hex: "E7F5DE")],
            glow: Color(hex: "6FBF8B").opacity(0.4),
            accent: Color(hex: "1E7A4B"),
            chip: Color(hex: "6FBF8B").opacity(0.2),
            chipLine: Color(hex: "4F9E6C").opacity(0.34),
            fill: Color(hex: "3E8C5E"),
            bubbleForeground: .white
        ),
        .heart: AccentColors(
            canvas: [Color(hex: "FDEAEC"), Color(hex: "FBE0E4"), Color(hex: "F6E6EE")],
            glow: Color(hex: "E85C6B").opacity(0.32),
            accent: Color(hex: "C2334A"),
            chip: Color(hex: "E85C6B").opacity(0.16),
            chipLine: Color(hex: "D1465A").opacity(0.3),
            fill: Color(hex: "C93B50"),
            bubbleForeground: .white
        ),
    ]

    /// The 158°, 3-stop canvas gradient every share card uses as its background.
    var canvasGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: canvas[0], location: 0),
                .init(color: canvas[1], location: 0.56),
                .init(color: canvas[2], location: 1),
            ]),
            startPoint: UnitPoint(x: 0.12, y: 0),
            endPoint: UnitPoint(x: 0.88, y: 1)
        )
    }

    /// The top-right radial glow every share card layers over its canvas.
    var glowOverlay: some View {
        RadialGradient(colors: [glow, .clear], center: UnitPoint(x: 0.78, y: 0.06), startRadius: 4, endRadius: 260)
    }
}
