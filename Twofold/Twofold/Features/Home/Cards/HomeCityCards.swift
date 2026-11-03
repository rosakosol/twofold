//
//  HomeCityCards.swift
//  Twofold
//
//  Home's cards about where the two of them are: the distance and its globe, the same-city card,
//  and the prompts shown while a home city is missing.
//

import SwiftUI

struct HomeCityPromptCard: View {
    let onTap: () -> Void

    var body: some View {
        SectionCard {
            Button {
                onTap()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See the distance between you")
                            .font(.headline)
                        Text("Turn on location access to light up the map.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "map").foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Shown when the only missing city is the partner's.
///
/// Deliberately not a button. `homeCityPromptCard`'s tap opens the location permission screen,
/// which sets *this* device's city — offering it here would ask somebody to grant a permission
/// they have already granted, and leave the map exactly as dark afterwards.
struct PartnerHomeCityPendingCard: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See the distance between you")
                        .font(.headline)
                    Text("\(appModel.partner.name) needs to turn on location access before the map can light up.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Subdued rather than `accent`: nothing here is tappable, and the accent colour
                // is what tells the rest of this screen that something is.
                Image(systemName: "map").foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

struct SameCityCard: View {
    let city: Place

    var body: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Same city")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("You're both in \(city.displayCity)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.coral)
            }
            Text("No distance to close right now")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct DistanceCard: View {
    @Environment(AppModel.self) private var appModel

    let distanceKm: Double
    let myCity: Place
    let partnerCity: Place
    let onShare: () -> Void
    let onOpenGlobe: () -> Void

    /// The 36pt distance (section 6, Home), scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 36

    var body: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance between you")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(MeasurementPreference.distanceLabel(km: distanceKm))
                        .font(.system(size: distanceSize, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                CircularNavButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share distance") {
                    onShare()
                }
            }
            // Hidden below 0.05% — anything less rounds to a deadpan, uninformative "0.0%" at
            // this line's own one-decimal precision (nearby but not exactly the same city, e.g.,
            // still shows the real km figure above just fine, but "that's 0.0% of the way around
            // the earth" reads as a bug, not a fact).
            if Geo.percentOfEarthCircumference(distanceKm) >= 0.05 {
                Text("\(Geo.percentOfEarthCircumference(distanceKm), format: .number.precision(.fractionLength(1)))% of the way around the Earth")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            RelationshipGlobeView(couple: appModel.session.couple, partnerACity: myCity, partnerBCity: partnerCity, activeTrip: appModel.travel.activeTrip)
                .frame(height: 260)
                // A preview, not a globe you turn here. Two reasons, and the first one predates
                // this card being tappable at all: a live `Map` inside a `ScrollView` competes for
                // every drag, so a swipe that meant "scroll Home" as often nudged the earth
                // instead. The second is that the tap below has to reach the card, and a `Map`
                // consumes taps whether or not it does anything with them. Turning it is what the
                // full-screen view exists for.
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous))
                // Added after `allowsHitTesting(false)`, so the badge is a sibling layered on top
                // of the inert map and takes taps normally. Order matters here: modifying the map
                // first and overlaying second is what keeps the button live.
                .overlay(alignment: .topTrailing) {
                    CircularNavButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "See the globe full screen") {
                        onOpenGlobe()
                    }
                    .padding(Theme.Spacing.sm)
                }
        }
        // The whole card, as asked. The share button keeps its own taps — it's a `Button`, so it
        // is hit first — and the globe above is inert by the time this gesture sees anything.
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenGlobe()
        }
    }
}
