//
//  MemoriesMapView.swift
//  Twofold
//

import SwiftUI
import MapKit
import PostHog

struct MemoriesMapView: View {
    var onTapAddMemory: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @State private var selectedCity: Place?
    /// Starts small (peek height) so the map's still visible/pannable underneath — swiping the
    /// sheet up, or tapping anywhere in the peek content, expands it to full height.
    @State private var sheetDetent: PresentationDetent = Self.peekDetent
    /// Drives the staggered pin entrance below — same pattern onboarding's `MapSellView` mock
    /// already uses, just against the real `citiesWithMemories` list instead of mock data.
    @State private var shownCityIDs: Set<UUID> = []

    private static let peekDetent: PresentationDetent = .height(220)

    /// Centers on the user's own home city when known — same "home city as location" surrogate
    /// the rest of the app already uses for weather/distance, so this needs no fresh location
    /// permission prompt just to open the map. Falls back to fitting all memory pins only when
    /// no home city is set yet.
    private var initialRegion: MKCoordinateRegion {
        if let homeCity = appModel.currentUser.homeCity {
            return MKCoordinateRegion(center: homeCity.coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }
        return Self.region(containing: appModel.citiesWithMemories.map(\.coordinate), padding: 0.3)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // `initialPosition` (seeded once, not a live two-way binding) rather than a
            // continuously-rebound `.automatic` `position:` — the latter keeps refitting to
            // content on re-render, which fights the user's own pinch/pan gestures instead of
            // letting them take over after the initial fit. Same fix as FlightMapView's zoom
            // bug. `interactionModes: .all` set explicitly rather than relying on the default.
            Map(initialPosition: .region(initialRegion), interactionModes: .all) {
                ForEach(appModel.citiesWithMemories) { city in
                    Annotation(city.city, coordinate: city.coordinate) {
                        Button {
                            sheetDetent = Self.peekDetent
                            selectedCity = city
                        } label: {
                            memoryPin(for: city)
                                .scaleEffect(shownCityIDs.contains(city.id) ? 1 : 0.4)
                                .opacity(shownCityIDs.contains(city.id) ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            // Tapping a marker's own Button consumes that tap before it reaches here, so this
            // only fires for taps that land elsewhere on the map — closes the marker panel the
            // same way tapping outside any other panel would, without needing to give up
            // `presentationBackgroundInteraction` (which is what lets pan/pinch reach the map
            // while the panel's still open).
            .onTapGesture {
                selectedCity = nil
            }
            .onAppear { animatePins() }
            // Adding a memory presents AddMemoryView as a sheet *over* this same view instance —
            // it never disappears/reappears, so `.onAppear` doesn't fire again on dismiss. Without
            // this, a newly-added city's pin renders into the Map's content (ForEach is reactive)
            // but stays permanently scaled-to-0/invisible, since `animatePins()` only ever ran once
            // and never added the new city's id to `shownCityIDs`. Switching to List and back used
            // to "fix" it only because that remounts this view, re-triggering `.onAppear`.
            .onChange(of: appModel.citiesWithMemories.map(\.id)) { _, newIDs in
                revealNewPins(newIDs)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: shownCityIDs)

            if appModel.citiesWithMemories.isEmpty {
                emptyStateHint
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.sm)
            }
        }
        .sheet(item: $selectedCity) { city in
            NavigationStack {
                MemoriesListView(initialLocationFilter: city)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if sheetDetent == Self.peekDetent { sheetDetent = .large }
                }
            )
            .presentationDetents([Self.peekDetent, .large], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: Self.peekDetent))
        }
        .postHogScreenView("Memories: Map")
    }

    /// Most recent memory's own photo, so the pin shows something real about that place
    /// instead of a generic icon — falls back to `MemoryPhotoView`'s own gradient+icon
    /// placeholder when that memory has no photo yet.
    private func memoryPin(for city: Place) -> some View {
        let cityMemories = appModel.memories(in: city)
        let mostRecent = cityMemories.max { $0.date < $1.date }

        return ZStack(alignment: .topTrailing) {
            Group {
                if let mostRecent {
                    MemoryPhotoView(memory: mostRecent, cornerRadius: 999)
                } else {
                    Circle().fill(Theme.cardBackground)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            if cityMemories.count > 1 {
                Text("\(cityMemories.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.heartRed, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
    }

    /// Same staggered-reveal timing `MapSellView`'s onboarding mock uses — each pin scales/fades
    /// in a beat after the last, rather than the whole set popping onto the map at once.
    private func animatePins() {
        shownCityIDs.removeAll()
        for (index, city) in appModel.citiesWithMemories.enumerated() {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.15 + Double(index) * 0.12)) {
                _ = shownCityIDs.insert(city.id)
            }
        }
    }

    /// Reveals just the cities not already shown — used after the initial `animatePins()` so a
    /// memory added later (e.g. via the "+" sheet) pops in on its own instead of staying invisible
    /// until this view happens to remount. See the `.onChange` comment above for why this exists.
    private func revealNewPins(_ cityIDs: [UUID]) {
        let newIDs = cityIDs.filter { !shownCityIDs.contains($0) }
        guard !newIDs.isEmpty else { return }
        for (index, id) in newIDs.enumerated() {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(Double(index) * 0.12)) {
                _ = shownCityIDs.insert(id)
            }
        }
    }

    private var emptyStateHint: some View {
        Button(action: onTapAddMemory) {
            SectionCard {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(Theme.skyBlue.opacity(0.15))
                        Image(systemName: "photo.badge.plus").foregroundStyle(Theme.skyBlue)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your first memory").font(.headline).foregroundStyle(Theme.ink)
                        Text("Tap to save a photo from a moment together.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Bounding box over however many memory-city pins exist, padded so pins aren't flush
    /// against the screen edge. Only seeds the map's *initial* camera (see `initialPosition`
    /// above) — doesn't handle antimeridian-spanning sets specially the way FlightMapView's
    /// two-point version does, since a slightly-off initial fit for round-the-world memories is
    /// a minor cosmetic issue, not a correctness one (the user can just zoom/pan from there).
    private static func region(containing coordinates: [CLLocationCoordinate2D], padding: Double) -> MKCoordinateRegion {
        guard let first = coordinates.first else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 20, longitude: 0), span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140))
        }
        guard coordinates.count > 1 else {
            return MKCoordinateRegion(center: first, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        }

        var minX = Double.greatestFiniteMagnitude, maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let minSize = 2_000_000.0
        let width = max(maxX - minX, minSize) * (1 + 2 * padding)
        let height = max(maxY - minY, minSize) * (1 + 2 * padding)
        let rect = MKMapRect(x: (minX + maxX) / 2 - width / 2, y: (minY + maxY) / 2 - height / 2, width: width, height: height)
        return MKCoordinateRegion(rect)
    }
}

#Preview {
    NavigationStack {
        MemoriesMapView()
            .environment(AppModel())
    }
}
