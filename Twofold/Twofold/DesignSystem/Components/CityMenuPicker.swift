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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button {
            showingSearch = true
        } label: {
            // Label and value side by side normally. At accessibility sizes they stack: side by
            // side, "Alex's city" broke mid-word and the city shrank to "Select…".
            if dynamicTypeSize.isAccessibilitySize {
                HStack {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(label).foregroundStyle(Theme.textSecondary)
                        value
                    }
                    Spacer(minLength: 0)
                    chevron
                }
                .padding()
                .onboardingFieldBackground()
            } else {
                HStack {
                    Text(label).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    value
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    chevron
                }
                .padding()
                .onboardingFieldBackground()
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSearch) {
            CitySearchView { place in
                selection = place
            }
        }
    }

    private var value: some View {
        Text(selection.map { $0.displayCity } ?? placeholder)
            .foregroundStyle(selection == nil ? Theme.textSecondary : Theme.textPrimary)
    }

    private var chevron: some View {
        Image(systemName: "chevron.up.chevron.down")
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
    }
}
