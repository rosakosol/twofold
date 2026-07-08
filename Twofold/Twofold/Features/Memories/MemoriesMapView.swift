//
//  MemoriesMapView.swift
//  Twofold
//

import SwiftUI
import MapKit

struct MemoriesMapView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedCity: Place?
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var cityForStrip: Place? {
        selectedCity ?? appModel.citiesWithMemories.first
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(position: $cameraPosition, selection: $selectedCity) {
                    ForEach(appModel.citiesWithMemories) { city in
                        Annotation(city.city, coordinate: city.coordinate) {
                            memoryPin(for: city)
                                .onTapGesture { selectedCity = city }
                        }
                        .tag(city)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))

                if let city = cityForStrip {
                    citySheet(for: city)
                        .padding(Theme.Spacing.md)
                }
            }
            .navigationTitle("Memories")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func memoryPin(for city: Place) -> some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(.white)
                .frame(width: 40, height: 40)
                .shadow(radius: 3)
                .overlay(Image(systemName: "photo.fill").foregroundStyle(Theme.skyBlue))
            Text("\(appModel.memories(in: city).count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Theme.heartRed, in: Circle())
                .offset(x: 6, y: -6)
        }
    }

    private func citySheet(for city: Place) -> some View {
        let cityMemories = appModel.memories(in: city)
        return SectionCard {
            HStack {
                VStack(alignment: .leading) {
                    Text(city.city).font(.headline)
                    Text("\(cityMemories.count) memories").font(.caption).foregroundStyle(Theme.subtleInk)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.subtleInk)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(cityMemories) { memory in
                        NavigationLink {
                            MemoryDetailView(memory: memory)
                        } label: {
                            MemoryPhotoPlaceholder(memory: memory)
                                .frame(width: 96, height: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

#Preview {
    MemoriesMapView()
        .environment(AppModel())
}
