//
//  MapSellView.swift
//  Twofold
//
//  Feature-education screen, same idea as LiveActivitySellView/WidgetSellView — a small
//  illustrative map pinned near the couple's real home city, if picked earlier in onboarding.
//  Comes right after MemoriesSellView's journal-style pitch, so this one is purely "and it's
//  all mapped to where it happened" — no fabricated photos, just generic aspirational pins.
//

import SwiftUI
import MapKit

struct MapSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var mapVisible = false

    private var homeCity: Place? { onboarding.homeCity }

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

                    Text("Available on the Memories map")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
                        mapVisible = true
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.widgetSell) }
        )
    }

    /// Non-interactive, real coordinates — the same technique `WelcomeView`'s background
    /// globe and `RelationshipGlobeView` use. Zoomed to a normal neighborhood view around the
    /// user's own home city rather than trying to fit both partners' cities — for a genuinely
    /// long-distance couple those can be entire continents apart, which would either force an
    /// unreadably wide zoom or an invalid coordinate span. A couple of small illustrative pins
    /// sit near the home city rather than pretending to mark specific real memories.
    private func memoryMap(homeCity: Place) -> some View {
        let region = MKCoordinateRegion(center: homeCity.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))
        let secondPin = CLLocationCoordinate2D(latitude: homeCity.coordinate.latitude + 0.06, longitude: homeCity.coordinate.longitude + 0.08)
        let thirdPin = CLLocationCoordinate2D(latitude: homeCity.coordinate.latitude - 0.05, longitude: homeCity.coordinate.longitude - 0.05)

        return Map(position: .constant(.region(region)), interactionModes: []) {
            Annotation("Where we met", coordinate: homeCity.coordinate) {
                mapPin(emoji: "💛")
            }
            Annotation("That sunset", coordinate: secondPin) {
                mapPin(emoji: "🌅")
            }
            Annotation("First trip together", coordinate: thirdPin) {
                mapPin(emoji: "✈️")
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func mapPin(emoji: String) -> some View {
        ZStack {
            Circle().fill(.white)
            Text(emoji).font(.system(size: 16))
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

#Preview {
    NavigationStack {
        MapSellView()
    }
    .environment(OnboardingModel())
}
