//
//  MemoryLocationSearchView.swift
//  Twofold
//
//  Address/POI search sheet for a memory's location — the memory equivalent of
//  `CitySearchView`, but permissive of full addresses instead of city-only results. A map sits
//  above the search list: it starts centered on the user's current location (reusing
//  `HomeLocationService`, the same one-shot "use my current location" flow the home-city picker
//  already uses) and doubles as a direct picker — tapping anywhere on it drops a pin there,
//  offering that exact spot as a selectable result alongside the text-search list below.
//

import SwiftUI
import MapKit
import CoreLocation
import PostHog

struct MemoryLocationSearchView: View {
    var onSelect: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var completer = MemoryLocationSearchCompleter()
    @State private var locationService = HomeLocationService()
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var droppedPin: CLLocationCoordinate2D?
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        UserAnnotation()
                        if let droppedPin {
                            Marker("Selected location", coordinate: droppedPin)
                                .tint(Theme.heartRed)
                        }
                    }
                    .onTapGesture { screenPoint in
                        guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                        droppedPin = coordinate
                    }
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
                .frame(height: 220)

                List {
                    if let droppedPin {
                        Button {
                            useDroppedPin(droppedPin)
                        } label: {
                            HStack {
                                Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.heartRed)
                                Text("Use this spot on the map").foregroundStyle(Theme.ink)
                            }
                        }
                    }

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
                .listStyle(.plain)
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
        .onAppear {
            locationService.requestCurrentLocation()
        }
        .onChange(of: locationService.state) { _, newState in
            guard case .resolved(let place) = newState else { return }
            withAnimation {
                cameraPosition = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
            }
        }
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

    /// Reverse-geocodes a tapped map coordinate into a `Place` — the label reads back whatever
    /// place/street name Core Location resolves for that exact spot, falling back to a plain
    /// lat/lon string on the rare pin that resolves to nothing nameable (open ocean, etc.).
    private func useDroppedPin(_ coordinate: CLLocationCoordinate2D) {
        isResolving = true
        errorMessage = nil
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)).first
            let label = [placemark?.name, placemark?.locality]
                .compactMap { $0 }
                .first ?? String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
            let place = Place(
                city: label,
                country: placemark?.country ?? "",
                iataCode: nil,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZoneIdentifier: placemark?.timeZone?.identifier
            )
            onSelect(place)
            dismiss()
            isResolving = false
        }
    }
}

#Preview {
    MemoryLocationSearchView(onSelect: { _ in })
}
