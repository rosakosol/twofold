//
//  MemoryLocationSearchView.swift
//  Twofold
//
//  Address/POI search sheet for a memory's location — the memory equivalent of
//  `CitySearchView`, but permissive of full addresses instead of city-only results.
//

import SwiftUI
import MapKit
import CoreLocation
import PostHog

struct MemoryLocationSearchView: View {
    var onSelect: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completer = MemoryLocationSearchCompleter()
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !completer.queryFragment.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        useTypedAddress(completer.queryFragment)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.heartRed)
                            Text("Use “\(completer.queryFragment)”").foregroundStyle(Theme.ink)
                        }
                    }
                }

                ForEach(completer.results, id: \.title) { completion in
                    Button {
                        resolve(completion)
                    } label: {
                        locationRow(title: completion.title, subtitle: completion.subtitle)
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
            .searchable(text: $completer.queryFragment, prompt: "Type an address or place")
            .navigationTitle("Memory location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .postHogScreenView("Memories: Location Search")
    }

    private func locationRow(title: String, subtitle: String) -> some View {
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
                let place = try await MemoryLocationSearchCompleter.resolve(completion)
                onSelect(place)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }

    /// Falls back to plain geocoding for addresses the completer doesn't surface a
    /// suggestion for — the typed text itself becomes the location's display label.
    private func useTypedAddress(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
                guard let placemark = placemarks.first, let location = placemark.location else {
                    throw CitySearchError.noCityFound
                }
                let place = Place(
                    city: trimmed,
                    country: placemark.country ?? "",
                    iataCode: nil,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZoneIdentifier: placemark.timeZone?.identifier
                )
                onSelect(place)
                dismiss()
            } catch {
                errorMessage = "Couldn't find that address."
            }
            isResolving = false
        }
    }
}

#Preview {
    MemoryLocationSearchView(onSelect: { _ in })
}
