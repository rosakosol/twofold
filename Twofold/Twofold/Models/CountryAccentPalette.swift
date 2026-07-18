//
//  CountryAccentPalette.swift
//  Twofold
//
//  A curated country → two-stop gradient mapping, loosely evoking each country's flag or
//  cultural palette — used by `RelationshipStatsShareCard` so a couple's most significant
//  destination (their longest trip, or their most-visited country) gives the shareable card its
//  own distinct color identity instead of every couple getting the same background. Deliberately
//  not exhaustive — falls back to the app's own sky-blue-to-green gradient for anything
//  unlisted, which reads as a perfectly good default, not a missing case.
//

import SwiftUI

enum CountryAccentPalette {
    private static let byCountry: [String: [Color]] = [
        "Japan": [Color(hex: "FFB7C5"), Color(hex: "3D2C3E")],
        "France": [Color(hex: "4B6CB7"), Color(hex: "C82E3C")],
        "Italy": [Color(hex: "2E9E5B"), Color(hex: "D64550")],
        "Spain": [Color(hex: "F5B841"), Color(hex: "C8253A")],
        "United States": [Color(hex: "3B4E8C"), Color(hex: "C13A4A")],
        "United Kingdom": [Color(hex: "2A3D7C"), Color(hex: "C8102E")],
        "Australia": [Color(hex: "1F3A6E"), Color(hex: "F4C542")],
        "New Zealand": [Color(hex: "1B2A4A"), Color(hex: "3E9E6E")],
        "Canada": [Color(hex: "D62839"), Color(hex: "F2F2F2")],
        "Mexico": [Color(hex: "2E7D4F"), Color(hex: "D6483A")],
        "Brazil": [Color(hex: "2E8B4F"), Color(hex: "F4C542")],
        "Argentina": [Color(hex: "6FB6E8"), Color(hex: "F4C542")],
        "Peru": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Chile": [Color(hex: "1F3A6E"), Color(hex: "C8253A")],
        "Germany": [Color(hex: "2B2B2B"), Color(hex: "D6483A")],
        "Netherlands": [Color(hex: "C8253A"), Color(hex: "2A3D7C")],
        "Belgium": [Color(hex: "2B2B2B"), Color(hex: "F4C542")],
        "Switzerland": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Austria": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Portugal": [Color(hex: "2E7D4F"), Color(hex: "D6483A")],
        "Greece": [Color(hex: "1F6FB6"), Color(hex: "F2F2F2")],
        "Turkey": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Sweden": [Color(hex: "1F5AA6"), Color(hex: "F4C542")],
        "Norway": [Color(hex: "1F3A6E"), Color(hex: "C8253A")],
        "Denmark": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Finland": [Color(hex: "1F5AA6"), Color(hex: "F2F2F2")],
        "Iceland": [Color(hex: "1F3A6E"), Color(hex: "6FB6E8")],
        "Ireland": [Color(hex: "2E9E5B"), Color(hex: "F4A63E")],
        "Poland": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Czech Republic": [Color(hex: "1F3A6E"), Color(hex: "C8253A")],
        "Croatia": [Color(hex: "1F3A6E"), Color(hex: "C8253A")],
        "China": [Color(hex: "C8253A"), Color(hex: "F4C542")],
        "Hong Kong": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Taiwan": [Color(hex: "1F3A6E"), Color(hex: "C8253A")],
        "South Korea": [Color(hex: "3B4E8C"), Color(hex: "C13A4A")],
        "Thailand": [Color(hex: "C8253A"), Color(hex: "1F3A6E")],
        "Vietnam": [Color(hex: "C8253A"), Color(hex: "F4C542")],
        "Singapore": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Malaysia": [Color(hex: "1F3A6E"), Color(hex: "F4C542")],
        "Indonesia": [Color(hex: "C8253A"), Color(hex: "F2F2F2")],
        "Philippines": [Color(hex: "1F5AA6"), Color(hex: "C8253A")],
        "India": [Color(hex: "F4A63E"), Color(hex: "2E7D4F")],
        "Nepal": [Color(hex: "C8253A"), Color(hex: "1F3A6E")],
        "Sri Lanka": [Color(hex: "D6483A"), Color(hex: "F4C542")],
        "United Arab Emirates": [Color(hex: "2E7D4F"), Color(hex: "C8253A")],
        "Egypt": [Color(hex: "F4C542"), Color(hex: "2B2B2B")],
        "Morocco": [Color(hex: "C8253A"), Color(hex: "2E7D4F")],
        "South Africa": [Color(hex: "2E7D4F"), Color(hex: "F4C542")],
        "Kenya": [Color(hex: "2B2B2B"), Color(hex: "C8253A")],
        "Fiji": [Color(hex: "1F5AA6"), Color(hex: "6FB6E8")],
    ]

    static func gradientColors(for country: String?) -> [Color] {
        guard let country, let match = byCountry[country] else {
            // Deepened versions of the app's own brand colors (`Theme.skyBlue`/`Theme.leafGreen`)
            // rather than the pale pastel `Theme.backgroundGradient` itself — this sits behind
            // fixed white text/dots (see `RelationshipStatsShareCard`), which the actual pastel
            // is far too light to hold legibly. This is the default most couples without a
            // curated country match will actually see.
            return [Color(hex: "1B5E82"), Color(hex: "1D6B4A")]
        }
        return match
    }
}
