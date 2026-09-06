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
    /// Drives `AddMemoryView`'s sheet when the per-location list's own empty state is tapped —
    /// separate from `selectedCity` since that one's sheet stays open underneath (adding a memory
    /// here shouldn't also close the location list it was tapped from).
    @State private var addMemoryPlace: Place?
    /// Starts small (peek height) so the map's still visible/pannable underneath — swiping the
    /// sheet up, or tapping anywhere in the peek content, expands it to full height.
    @State private var sheetDetent: PresentationDetent = Self.peekDetent
    /// Drives the staggered pin entrance below — same pattern onboarding's `MapSellView` mock
    /// already uses, just against the real `citiesWithMemories` list instead of mock data.
    @State private var shownCityIDs: Set<UUID> = []
    /// Seeded from `initialRegion` on first appearance and otherwise only written when a city is
    /// searched. See the `Map` below for why it is bound rather than an `initialPosition`.
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didSeedCamera = false
    @State private var showingCitySearch = false

    // Not private, so SheetDetentWidthTests measures the detents this view actually uses
    // rather than its own copies of them — a copy would keep passing after a revert here.
    static let peekDetent: PresentationDetent = .height(220)
    /// The expanded height, and deliberately not `.large`.
    ///
    /// A sheet below full height is drawn as an inset card — 8pt in from each edge, 386pt wide on
    /// a 402pt screen. `.large` is the one detent that isn't: it goes edge to edge at the full 402.
    /// So dragging this panel up didn't just make it taller, it made it wider at the same time, and
    /// the card appeared to grow sideways out of the screen as you pulled it.
    ///
    /// A fraction just short of full keeps the card exactly where it was. Measured at 402x874:
    /// peek sits at x=8 w=386, `.large` at x=0 w=402, and `.fraction(0.98)` at x=8 w=386 — same
    /// width as the peek, ~823pt tall against `.large`'s 874.
    static let expandedDetent: PresentationDetent = .fraction(0.98)

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
            // A bound `position` seeded once, and written to only when the person asks the map to
            // go somewhere (searching a city, below). The thing that fights pinch and pan is a
            // `.automatic` position rebound on every render, which keeps refitting to content —
            // same bug FlightMapView had. A binding the view leaves alone does not do that, and it
            // is the only way to move the camera on demand.
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(appModel.citiesWithMemories) { city in
                    // Labelled with the memory itself rather than the place. The pin already
                    // shows that memory's photo and sits on the map at its location, so repeating
                    // the city underneath said nothing the map wasn't already saying — where a
                    // title says which memory this is.
                    Annotation(pinTitle(for: city), coordinate: city.coordinate) {
                        Button {
                            sheetDetent = Self.peekDetent
                            selectedCity = city
                        } label: {
                            memoryPin(for: city)
                                .scaleEffect(shownCityIDs.contains(city.id) ? 1 : 0.4)
                                .opacity(shownCityIDs.contains(city.id) ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(memoryPinLabel(for: city))
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
            .onAppear {
                animatePins()
                // Once. Re-seeding on every appearance would throw away wherever the person had
                // panned to the last time they looked at this screen.
                if !didSeedCamera {
                    cameraPosition = .region(initialRegion)
                    didSeedCamera = true
                }
            }
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

            VStack(spacing: Theme.Spacing.sm) {
                searchButton
                if appModel.citiesWithMemories.isEmpty {
                    emptyStateHint
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)
        }
        .sheet(isPresented: $showingCitySearch) {
            CitySearchView { place in
                // Wide enough to take in a city and the towns around it, so memories just outside
                // it are on screen too rather than needing another pinch to find.
                withAnimation(.easeInOut(duration: 0.6)) {
                    cameraPosition = .region(
                        MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
                    )
                }
            }
        }
        .sheet(item: $selectedCity) { city in
            NavigationStack {
                // Previously left at its default no-op closure — tapping this location's own
                // "Add your first memory" empty-state hint did nothing at all, since only
                // MemoriesView's tab-mode instantiation ever wired onTapAddMemory through.
                MemoriesListView(initialLocationFilter: city, onTapAddMemory: { addMemoryPlace = city })
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if sheetDetent == Self.peekDetent { sheetDetent = Self.expandedDetent }
                }
            )
            .presentationDetents([Self.peekDetent, Self.expandedDetent], selection: $sheetDetent)
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: Self.peekDetent))
        }
        .sheet(item: $addMemoryPlace) { place in
            AddMemoryView(initialPlace: place)
        }
        .postHogScreenView("Memories: Map")
    }

    /// Somewhere to type when the memory you want is on the other side of the world.
    ///
    /// The map opens on your own home city, which is the right place to start and the wrong place
    /// to be when the memories you are looking for are your partner's. Panning there by hand across
    /// an ocean is a lot of dragging; this jumps.
    private var searchButton: some View {
        Button {
            showingCitySearch = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                Text("Search for a place")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .themedCardBackground(cornerRadius: Theme.Radius.pill)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search for a place on the map")
    }

    /// Most recent memory's own photo, so the pin shows something real about that place
    /// instead of a generic icon — falls back to `MemoryPhotoView`'s own gradient+icon
    /// placeholder when that memory has no photo yet.
    private func memoryPinLabel(for city: Place) -> String {
        let count = appModel.memories(in: city).count
        return "\(city.displayCity), \(count) \(count == 1 ? "memory" : "memories")"
    }

    /// The label under the pin: the memory whose photo the pin is showing, so the caption and the
    /// picture are about the same thing. Where a place holds several, the newest one names it and
    /// the badge on the pin already says how many more there are. Falls back to the place only when
    /// a memory has no title to show.
    private func pinTitle(for city: Place) -> String {
        let newest = appModel.memories(in: city).max { $0.date < $1.date }
        let title = newest?.title.trimmingCharacters(in: .whitespaces) ?? ""
        return title.isEmpty ? city.displayCity : title
    }

    /// A small print of the photo, framed the way the memory detail screen frames it: square,
    /// white border, slight tilt. It used to be a 44pt circle, which is a map marker rather than a
    /// picture — too small to make out what the photo was of, and cropped to a shape that fights
    /// the rectangle every photo actually is. At 64pt square you can tell your memories apart
    /// without opening them.
    private func memoryPin(for city: Place) -> some View {
        let cityMemories = appModel.memories(in: city)
        let mostRecent = cityMemories.max { $0.date < $1.date }

        return ZStack(alignment: .topTrailing) {
            Group {
                if let mostRecent {
                    MemoryPhotoView(memory: mostRecent, cornerRadius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.cardBackground)
                }
            }
            .frame(width: 64, height: 64)
            .padding(5)
            .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
            // Tilted like the detail screen's print, a touch further: two degrees reads as a
            // rendering mistake at this size, where four reads as deliberate.
            .rotationEffect(.degrees(-4))

            if cityMemories.count > 1 {
                Text("\(cityMemories.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.heartRed, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
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
            // Flat even in dark mode (`appliesDarkWash: false`) — this floats directly over the
            // map itself, and `SectionCard`'s usual dark-mode wash is the same blue-to-green tint
            // as the map underneath it, so the card all but vanished into it instead of standing
            // out as a hint to tap.
            SectionCard(appliesDarkWash: false) {
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
