//
//  FlightStickerStyle.swift
//  Twofold
//

import SwiftUI

/// The Boarding Pass card's own palette — shared by the standalone Boarding Pass share page and
/// the smaller sticker composited onto the Route Map page (see `FlightShareView`), so choosing a
/// style updates both since they render the same `BoardingPassShareCard` at two sizes. Same
/// "3-case palette enum + picker row" shape as `DistanceShareTheme`.
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

    var backgroundColor: Color {
        switch self {
        case .light: .white
        case .dark: Color(hex: "10161F")
        case .brand: Theme.skyBlue
        }
    }

    var accentColor: Color {
        switch self {
        case .light: Theme.skyBlue
        case .dark: Color(hex: "6FD3FF")
        case .brand: .white
        }
    }

    var primaryTextColor: Color {
        switch self {
        case .light: Theme.ink
        case .dark: .white
        case .brand: .white
        }
    }

    var secondaryTextColor: Color {
        switch self {
        case .light: Theme.subtleInk
        case .dark: .white.opacity(0.6)
        case .brand: .white.opacity(0.75)
        }
    }

    /// The accent block's own text/icon color — the accent block is a solid fill of
    /// `accentColor`, so this needs to read against *that*, not the card's own background.
    var onAccentColor: Color {
        switch self {
        case .light, .dark: .white
        case .brand: Theme.skyBlue
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
