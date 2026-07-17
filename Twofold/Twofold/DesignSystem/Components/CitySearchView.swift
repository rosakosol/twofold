//
//  CitySearchView.swift
//  Twofold
//
//  Live city search sheet backing CityMenuPicker. Shows the curated common-cities list as
//  quick picks (pre-seeded in the backend, so selecting one is instant) when the search
//  field is empty, live MapKit results once the user starts typing.
//

import SwiftUI
import MapKit

struct CitySearchView: View {
    var onSelect: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appModel
    @State private var completer = CitySearchCompleter()
    @State private var isResolving = false
    @State private var errorMessage: String?

    /// Your own and (once connected) your partner's home city — the two places someone adding
    /// a trip is overwhelmingly likely to actually pick, so they lead the suggestions ahead of
    /// the generic curated list rather than requiring a search.
    private var homeCitySuggestions: [(label: String, place: Place)] {
        var suggestions: [(label: String, place: Place)] = []
        if let city = appModel.currentUser.homeCity {
            suggestions.append(("Your city", city))
        }
        if appModel.partnerConnected, let city = appModel.partner.homeCity {
            suggestions.append(("\(appModel.partner.name)'s city", city))
        }
        return suggestions
    }

    var body: some View {
        NavigationStack {
            List {
                if completer.queryFragment.isEmpty {
                    if !homeCitySuggestions.isEmpty {
                        Section("Your Cities") {
                            ForEach(homeCitySuggestions, id: \.place.id) { suggestion in
                                Button {
                                    onSelect(suggestion.place)
                                    dismiss()
                                } label: {
                                    cityRow(title: suggestion.place.displayCity, subtitle: suggestion.label)
                                }
                            }
                        }
                    }

                    Section("Suggested") {
                        ForEach(Place.commonCities) { place in
                            Button {
                                onSelect(place)
                                dismiss()
                            } label: {
                                cityRow(title: place.city, subtitle: place.country)
                            }
                        }
                    }
                } else {
                    ForEach(completer.results, id: \.title) { completion in
                        Button {
                            resolve(completion)
                        } label: {
                            cityRow(title: completion.title, subtitle: completion.subtitle)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                }
            }
            .overlay {
                if isResolving {
                    ProgressView()
                }
            }
            .searchable(text: $completer.queryFragment, prompt: "Search for a city")
            .navigationTitle("Choose a city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func cityRow(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Theme.ink)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
    }

    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let place = try await CitySearchCompleter.resolve(completion)
                onSelect(place)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }
}

#Preview {
    CitySearchView(onSelect: { _ in })
        .environment(AppModel())
}
