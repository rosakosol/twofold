//
//  MemoriesMapView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct MemoriesMapView: View {
    var onTapAddMemory: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedCity: Place?
    /// Starts small (peek height) so the map's still visible/pannable underneath — swiping the
    /// sheet up, or tapping anywhere in the peek content, expands it to full height.
    @State private var sheetDetent: PresentationDetent = Self.peekDetent

    private static let peekDetent: PresentationDetent = .height(220)

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $cameraPosition) {
                ForEach(appModel.citiesWithMemories) { city in
                    Annotation(city.city, coordinate: city.coordinate) {
                        Button {
                            sheetDetent = Self.peekDetent
                            selectedCity = city
                        } label: {
                            memoryPin(for: city)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))

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
}

#Preview {
    NavigationStack {
        MemoriesMapView()
            .environment(AppModel())
    }
}
