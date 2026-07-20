//
//  CityMenuPicker.swift
//  Twofold
//

import SwiftUI

/// A button that opens live city search (`CitySearchView`), reused by trip
/// origin/destination pickers, home-city pickers, and the add-memory location field.
struct CityMenuPicker: View {
    let label: String
    @Binding var selection: Place?
    var placeholder: String = "Select a city"

    @State private var showingSearch = false

    var body: some View {
        Button {
            showingSearch = true
        } label: {
            HStack {
                Text(label).foregroundStyle(Theme.subtleInk)
                Spacer()
                Text(selection.map { $0.displayCity } ?? placeholder)
                    .foregroundStyle(selection == nil ? Theme.subtleInk : Theme.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSearch) {
            CitySearchView { place in
                selection = place
            }
        }
    }
}
