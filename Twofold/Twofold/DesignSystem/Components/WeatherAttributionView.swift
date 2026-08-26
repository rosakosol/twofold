//
//  WeatherAttributionView.swift
//  Twofold
//
//  The Apple Weather trademark plus a link to Apple's legal attribution page — required wherever
//  WeatherKit data is displayed, and a condition of using the framework at all. Twofold shows a
//  temperature in two places: the Home time card (this view sits under it) and the Time & Weather
//  widget, which can't host a tappable link and carries the mark alone.
//
//  Deliberately the text mark rather than the artwork `WeatherAttribution` also vends: the marks
//  are remote images, and an async image that may fail to load is a poor carrier for something
//  that has to be present every time the temperature is. The trademark itself is the text.
//

import SwiftUI

struct WeatherAttributionView: View {
    @State private var legalURL: URL?

    var body: some View {
        Group {
            if let legalURL {
                Link(destination: legalURL) {
                    label.underline()
                }
            } else {
                // Before the URL resolves, the mark still shows — it's the trademark that must
                // always accompany the data; the link is the part that can arrive a beat later.
                label
            }
        }
        .accessibilityLabel("Weather data by Apple Weather. Opens Apple's legal attribution page.")
        .task {
            legalURL = await TwofoldWeatherService.legalAttributionURL()
        }
    }

    private var label: some View {
        Text(appleWeatherMark)
            .font(.caption2)
            .foregroundStyle(Theme.subtleInk)
    }
}

#Preview {
    WeatherAttributionView()
        .padding()
        .background(Theme.backgroundGradient)
}
