//
//  FlightStickerStyle.swift
//  Twofold
//

import SwiftUI

/// The Boarding Pass card's own palette — shared by the standalone Boarding Pass share page and
/// the smaller sticker composited onto the Route Map page (see `FlightShareView`), so choosing a
/// style updates both since they render the same `BoardingPassShareCard` at two sizes. Same
/// "3-case palette enum + picker row" shape as `DistanceShareTheme`.
///
/// Every color below is a fixed hex, never a `Theme.*`/`Color(light:dark:)` token — each case is
/// an explicit, appearance-independent pick (like `DistanceShareTheme.dark`/`.pink`), not a
/// system-light/dark pairing. `.light` used to lean on `Theme.ink`/`Theme.subtleInk` for its text,
/// which resolve to their *dark*-appearance (near-white) values whenever the system itself is in
/// dark mode — invisible white-on-white text on this style's fixed white card, regardless of it
/// being the "Light" pick. Same reasoning ruled out `Theme.skyBlue`/`Theme.skyBlueText` here too.
enum FlightStickerStyle: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case brand = "Brand"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .light: "sun.max.fill"
        case .dark: "moon.stars.fill"
        case .brand: "airplane.circle.fill"
        }
    }

    /// `.dark`'s fill is the dark-mode/Daylight handoff's own dark-"sky" canvas base tone.
    /// `.brand`'s used to be the brand fill blue (`#4FA9E0`) with *all* of the card's text — logo,
    /// passenger line, labels — in white on top of it; that blue is light enough that the white
    /// text read as "very difficult to see" across the board. Deepened to the handoff's own
    /// text-safe blue (`#1F6F9E`) instead, which is what that hex is actually calibrated for.
    var backgroundColor: Color {
        switch self {
        case .light: .white
        case .dark: Color(hex: "0C2233")
        case .brand: Color(hex: "1F6F9E")
        }
    }

    /// The pass block's solid fill — needs to be dark/saturated enough to carry bold white
    /// content reliably. The previous values (`Theme.skyBlue` light, `#8ACFF5` dark) were each
    /// one shade too light for that: `#8ACFF5` in particular is the handoff's *text/icon* tone,
    /// not its fill tone, so white text on top of it read the same "difficult to see" way.  Using
    /// the actual deepened fill hues (`#2F82BE` light, `#4FA9E0` dark — Daylight's own "deepened
    /// so white passes on it" blue) is the fix.
    var accentColor: Color {
        switch self {
        case .light: Color(hex: "2F82BE")
        case .dark: Color(hex: "4FA9E0")
        case .brand: .white
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .light: Color(hex: "16232F")
        case .dark: Color(hex: "F4F9FC")
        case .brand: .white
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .light: Color(hex: "52657A")
        case .dark: Color(hex: "F4F9FC").opacity(0.6)
        case .brand: .white.opacity(0.75)
        }
    }

    /// The accent block's own text/icon color — the accent block is a solid fill of
    /// `accentColor`, so this needs to read against *that*, not the card's own background.
    /// `.brand`'s block is a white fill, so its text needs a fixed deep blue rather than a token
    /// that could resolve to its pale appearance depending on the system's own light/dark setting.
    var onAccentColor: Color {
        switch self {
        case .light, .dark: .white
        case .brand: Color(hex: "1F6F9E")
        }
    }
}

struct FlightStickerStylePicker: View {
    @Binding var selection: FlightStickerStyle

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(FlightStickerStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: style.icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selection == style ? Theme.skyBlue : Theme.cardBackground, in: Circle())
                            .foregroundStyle(selection == style ? .white : Theme.ink)
                        Text(style.rawValue).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
