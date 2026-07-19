//
//  MapSellView.swift
//  Twofold
//
//  Feature-education screen, same idea as LiveActivitySellView/WidgetSellView — a small
//  illustrative map pinned near the couple's real home city, if picked earlier in onboarding.
//  Comes right after MemoriesSellView's journal-style pitch, so this one is purely "and it's
//  all mapped to where it happened." Markers reuse the exact visual from the real
//  `MemoriesMapView.memoryPin` (circular photo, white ring, shadow, count badge) against the
//  same mock `Memory` values MemoriesSellView uses, fading/scaling in one at a time with a
//  light haptic tap each — same `shownCards` + `.sensoryFeedback(.impact(weight: .light))`
//  pattern already established in NotificationsSellView.
//

import SwiftUI
import MapKit

struct MapSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var mapVisible = false
    @State private var shownPins: Set<Int> = []

    private var homeCity: Place? { onboarding.homeCity }

    private struct MockPin {
        let memory: Memory
        let coordinate: CLLocationCoordinate2D
        let count: Int
    }

    private func mockPins(around homeCity: Place) -> [MockPin] {
        let calendar = Calendar.current
        return [
            MockPin(
                memory: Memory(title: "Where we met", place: homeCity, date: calendar.date(byAdding: .month, value: -4, to: .now) ?? .now, note: "", photoSeed: 2),
                coordinate: homeCity.coordinate,
                count: 3
            ),
            MockPin(
                memory: Memory(title: "Watching the sunset", place: homeCity, date: calendar.date(byAdding: .day, value: -23, to: .now) ?? .now, note: "", photoSeed: 0),
                coordinate: CLLocationCoordinate2D(latitude: homeCity.coordinate.latitude + 0.06, longitude: homeCity.coordinate.longitude + 0.08),
                count: 1
            ),
            MockPin(
                memory: Memory(title: "Our first kiss", place: homeCity, date: calendar.date(byAdding: .month, value: -2, to: .now) ?? .now, note: "", photoSeed: 1),
                coordinate: CLLocationCoordinate2D(latitude: homeCity.coordinate.latitude - 0.05, longitude: homeCity.coordinate.longitude - 0.05),
                count: 1
            ),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            title: "Every memory, right on the map 🗺️",
            subtitle: "See where your relationship has happened, one pin at a time.",
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    if let homeCity {
                        memoryMap(homeCity: homeCity)
                            .scaleEffect(mapVisible ? 1 : 0.9)
                            .opacity(mapVisible ? 1 : 0)
                    }
                }
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
                        mapVisible = true
                    }
                    animatePins(count: homeCity.map { mockPins(around: $0).count } ?? 0)
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.widgetSell) }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: shownPins)
    }

    /// Non-interactive, real coordinates — the same technique `WelcomeView`'s background
    /// globe and `RelationshipGlobeView` use. Zoomed to a normal neighborhood view around the
    /// user's own home city rather than trying to fit both partners' cities — for a genuinely
    /// long-distance couple those can be entire continents apart, which would either force an
    /// unreadably wide zoom or an invalid coordinate span.
    private func memoryMap(homeCity: Place) -> some View {
        let region = MKCoordinateRegion(center: homeCity.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        let pins = mockPins(around: homeCity)

        return Map(position: .constant(.region(region)), interactionModes: []) {
            ForEach(Array(pins.enumerated()), id: \.offset) { index, pin in
                Annotation(pin.memory.title, coordinate: pin.coordinate) {
                    memoryPin(pin)
                        .scaleEffect(shownPins.contains(index) ? 1 : 0.4)
                        .opacity(shownPins.contains(index) ? 1 : 0)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Same structure as the real `MemoriesMapView.memoryPin` — circular photo, white ring,
    /// drop shadow, red count badge when more than one memory shares the spot.
    private func memoryPin(_ pin: MockPin) -> some View {
        ZStack(alignment: .topTrailing) {
            OnboardingMemoryImage(seed: pin.memory.photoSeed, cornerRadius: 999)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            if pin.count > 1 {
                Text("\(pin.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.heartRed, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
    }

    private func animatePins(count: Int) {
        shownPins.removeAll()
        for index in 0..<count {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(0.3 + Double(index) * 0.35)) {
                _ = shownPins.insert(index)
            }
        }
    }
}

#Preview {
    NavigationStack {
        MapSellView()
    }
    .environment(OnboardingModel())
}
