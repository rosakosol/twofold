//
//  TripsCarouselCards.swift
//  Twofold
//
//  The cards for the Travel sheet's peek height, floating over the globe: the same rows as the
//  expanded list (`TripRowView`, `FlightRowView`) in card chrome, so a trip or flight looks the
//  same in both.
//

import SwiftUI

struct TripCarouselCard: View {
    let trip: Trip
    let travelers: [Person]

    var body: some View {
        TripRowView(trip: trip, travelers: travelers)
            .padding(Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCardBackground(cornerRadius: Theme.Radius.card)
            .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, y: Theme.Shadow.y)
    }
}

struct FlightCarouselCard: View {
    let flight: Flight

    var body: some View {
        FlightRowView(flight: flight)
            .padding(Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCardBackground(cornerRadius: Theme.Radius.card)
            .shadow(color: Theme.Shadow.color, radius: Theme.Shadow.radius, y: Theme.Shadow.y)
    }
}

#Preview {
    ZStack {
        ScreenBackground()
        VStack {
            TripCarouselCard(trip: MockData.reunionTrip, travelers: [MockData.rosa, MockData.dara])
            FlightCarouselCard(flight: MockData.activeFlight)
        }
    }
}
