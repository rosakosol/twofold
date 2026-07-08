//
//  CityMenuPicker.swift
//  Twofold
//

import SwiftUI

/// A menu-style picker over `Place.commonCities`, reused by trip origin/destination
/// pickers and the home-city pickers.
struct CityMenuPicker: View {
    let label: String
    @Binding var selection: Place?
    var placeholder: String = "Select a city"

    var body: some View {
        Menu {
            ForEach(Place.commonCities) { place in
                Button("\(place.city), \(place.country)") { selection = place }
            }
        } label: {
            HStack {
                Text(label).foregroundStyle(Theme.subtleInk)
                Spacer()
                Text(selection.map { $0.city } ?? placeholder)
                    .foregroundStyle(selection == nil ? Theme.subtleInk : Theme.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}
