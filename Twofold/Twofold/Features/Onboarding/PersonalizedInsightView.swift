//
//  PersonalizedInsightView.swift
//  Twofold
//
//  The distance-reveal moment — the first emotional payoff of onboarding. Staged entrance
//  animations with haptics, a fast rolling count-up of the distance, a real 2D map with
//  both partners as markers joined by a geodesic path, a real-world comparison for the
//  number, and a shareable snapshot card (pure SwiftUI — ImageRenderer can't rasterize
//  MapKit views, so the card re-draws the moment instead of embedding the live map).
//  Real distance/timezone math only (`Geo.distanceKm`, `Place.timeZone`), never a
//  fabricated number. Couples in the same city get adapted copy instead of an awkward
//  "0 km apart".
//

import SwiftUI
import MapKit
import UIKit

struct PersonalizedInsightView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(\.displayScale) private var displayScale

    /// Drives the staged reveal: 1 = map, 2 = distance count-up, 3 = comparison line,
    /// 4 = stat tiles + buttons. Also the trigger for the per-stage haptics.
    @State private var stage = 0
    @State private var displayedKm: Double = 0

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    private var sameCity: Bool {
        guard let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return false }
        return mine.city == theirs.city && mine.country == theirs.country
    }

    private var distanceKm: Double? {
        guard !sameCity, let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return nil }
        return Geo.distanceKm(mine.coordinate, theirs.coordinate)
    }

    private var hoursApart: Int? {
        guard !sameCity, let mine = onboarding.homeCity?.timeZone, let theirs = onboarding.partnerCity?.timeZone else { return nil }
        let hours = Int((Double(theirs.secondsFromGMT() - mine.secondsFromGMT()) / 3600).rounded())
        return hours == 0 ? nil : abs(hours)
    }

    var body: some View {
        if let distanceKm, let myCity = onboarding.homeCity, let partnerCity = onboarding.partnerCity {
            distanceReveal(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity)
        } else {
            sameCityFallback
        }
    }

    // MARK: - Same-city / missing-data fallback

    /// The pre-existing calm copy for couples who share a city (or entered no cities) —
    /// there's no distance to dramatize, so no count-up, map, or comparison.
    private var sameCityFallback: some View {
        OnboardingScaffold(
            title: sameCity ? "Home is \(onboarding.homeCity?.city ?? "the same city") ❤️" : "You're apart right now ❤️",
            subtitle: "When \(partnerName) is away, Twofold helps you keep up with \(onboarding.partnerPossessive) journey home.",
            content: { EmptyView() },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.notificationsSell) }
        )
    }

    // MARK: - Distance reveal

    private func distanceReveal(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                mapCard(myCity: myCity, partnerCity: partnerCity)
                    .opacity(stage >= 1 ? 1 : 0)
                    .scaleEffect(stage >= 1 ? 1 : 0.92)
                    .offset(y: stage >= 1 ? 0 : 12)

                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(Text(displayedKm, format: .number.precision(.fractionLength(0))).font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.skyBlue)) \(Text("km").font(.title2.weight(.bold)).foregroundStyle(Theme.leafGreen))")
                    Text("apart")
                        .font(.headline)
                        .foregroundStyle(Theme.subtleInk)
                }
                .frame(maxWidth: .infinity)
                .opacity(stage >= 2 ? 1 : 0)

                Text(Self.comparison(for: distanceKm))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .opacity(stage >= 3 ? 1 : 0)
                    .offset(y: stage >= 3 ? 0 : 10)

                HStack(spacing: Theme.Spacing.lg) {
                    if let hoursApart {
                        StatTile(icon: "clock", value: "\(hoursApart)h", label: "Time difference", tint: Theme.leafGreen)
                    }
                    StatTile(
                        icon: "globe",
                        value: "\(Geo.percentOfEarthCircumference(distanceKm).formatted(.number.precision(.fractionLength(0))))%",
                        label: "Around the Earth",
                        tint: Theme.heartRed
                    )
                }
                .opacity(stage >= 4 ? 1 : 0)
                .offset(y: stage >= 4 ? 0 : 10)
            }
            .padding(Theme.Spacing.lg)
        }
        .safeAreaInset(edge: .bottom) { bottomBar(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity) }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: stage) { _, newStage in
            switch newStage {
            case 1: .impact(weight: .light)
            case 2: .impact(weight: .medium)
            case 3: .impact(weight: .light)
            case 4: .success
            default: nil
            }
        }
        .task {
            // Re-appearing (e.g. navigating back) skips the theatrics and shows the
            // finished state immediately.
            guard stage == 0 else {
                displayedKm = distanceKm
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { stage = 2 }
            await rollDistance(to: distanceKm)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { stage = 3 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { stage = 4 }
        }
    }

    /// Fast, ease-out rolling count-up — the number spins quickly through most of the range
    /// then settles on the real value, so the reveal isn't instant but never drags.
    private func rollDistance(to target: Double) async {
        let steps = 40
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let eased = 1 - pow(1 - progress, 3)
            displayedKm = target * eased
            try? await Task.sleep(for: .milliseconds(28))
        }
        displayedKm = target
    }

    // MARK: - Map

    private func mapCard(myCity: Place, partnerCity: Place) -> some View {
        Map(initialPosition: .region(Self.region(containing: myCity.coordinate, partnerCity.coordinate)), interactionModes: []) {
            Annotation(myCity.city, coordinate: myCity.coordinate) {
                avatarMarker(onboarding.selfPhotoData, tint: Theme.skyBlue)
            }
            Annotation(partnerCity.city, coordinate: partnerCity.coordinate) {
                avatarMarker(onboarding.partnerPhotoData, tint: Theme.heartRed)
            }
            MapPolyline(coordinates: [myCity.coordinate, partnerCity.coordinate], contourStyle: .geodesic)
                .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func avatarMarker(_ photoData: Data?, tint: Color) -> some View {
        ZStack {
            if let uiImage = photoData.flatMap(UIImage.init(data:)) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    /// A region framing both cities with breathing room, computed via `MKMapPoint`/`MKMapRect`
    /// (Mercator projection space) rather than naive lat/lon degree arithmetic. The old
    /// approach produced spans of 150–340+ degrees for genuinely distant pairs (e.g.
    /// Melbourne–London) — MapKit doesn't reliably render annotations/polylines for a region
    /// that wide, so the map looked static and empty for exactly the couples this screen is
    /// most dramatic for. `MKMapRect` handles arbitrary distances (including near-antipodal
    /// pairs) correctly since it's the same projection math MapKit uses internally.
    private static func region(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let pointA = MKMapPoint(a)
        let pointB = MKMapPoint(b)
        // A minimum size in map points (~ a couple hundred km) so two very close (but not
        // identical-city) coordinates don't produce a near-zero rect that zooms in absurdly.
        let minSize = 2_000_000.0
        let rect = MKMapRect(
            x: min(pointA.x, pointB.x),
            y: min(pointA.y, pointB.y),
            width: max(abs(pointA.x - pointB.x), minSize),
            height: max(abs(pointA.y - pointB.y), minSize)
        )
        // 40% padding on each side so the markers sit inside the frame, not glued to its edges.
        let padded = rect.insetBy(dx: -rect.width * 0.4, dy: -rect.height * 0.4)
        return MKCoordinateRegion(padded)
    }

    // MARK: - Comparison copy

    /// Well-known country lengths/widths (approximate, in km) to make the number tangible.
    /// Picked by closest ratio so e.g. 6,054 km reads as "about the width of Canada".
    private static let distanceComparisons: [(km: Double, label: String)] = [
        (250, "the length of Wales"),
        (550, "the length of England"),
        (1_000, "the length of France"),
        (1_600, "the length of Sweden"),
        (2_900, "the width of India"),
        (4_000, "the width of Australia"),
        (4_300, "the width of the USA"),
        (5_500, "the width of Canada"),
        (9_000, "the width of Russia"),
        (10_000, "a quarter of the way around the Earth"),
        (20_000, "halfway around the Earth"),
    ]

    private static func comparison(for km: Double) -> String {
        guard km >= 150 else { return "Closer than you think ❤️" }
        let nearest = distanceComparisons.min {
            abs(log($0.km / km)) < abs(log($1.km / km))
        }!
        return "That's about \(nearest.label) 🌏"
    }

    // MARK: - Bottom bar + snapshot

    private func bottomBar(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                onboarding.path.append(.notificationsSell)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)

            ShareLink(
                item: renderSnapshot(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity),
                preview: SharePreview(
                    "\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km apart",
                    image: renderSnapshot(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity)
                )
            ) {
                Label("Save this moment", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(Theme.Spacing.lg)
        // Same soft scrim treatment as OnboardingScaffold's bottom bar.
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.backgroundBottom.opacity(0), location: 0),
                    .init(color: Theme.backgroundBottom, location: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .opacity(stage >= 4 ? 1 : 0)
    }

    @MainActor
    private func renderSnapshot(distanceKm: Double, myCity: Place, partnerCity: Place) -> Image {
        let renderer = ImageRenderer(
            content: DistanceSnapshotCard(
                distanceKm: distanceKm,
                comparison: Self.comparison(for: distanceKm),
                myCity: myCity,
                partnerCity: partnerCity,
                selfPhoto: onboarding.selfPhotoData.flatMap(UIImage.init(data:)),
                partnerPhoto: onboarding.partnerPhotoData.flatMap(UIImage.init(data:))
            )
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

// MARK: - Snapshot card

/// Pure-SwiftUI rendering of the distance moment for sharing — ImageRenderer can't
/// rasterize MapKit views, so this re-draws the reveal (avatars joined by a dashed path
/// with a heart) instead of embedding the live map.
private struct DistanceSnapshotCard: View {
    let distanceKm: Double
    let comparison: String
    let myCity: Place
    let partnerCity: Place
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                avatar(selfPhoto, tint: Theme.skyBlue)

                Line()
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                    .frame(height: 2)
                    .overlay {
                        Text("❤️")
                            .font(.title3)
                    }

                avatar(partnerPhoto, tint: Theme.heartRed)
            }

            VStack(spacing: Theme.Spacing.xs) {
                Text("\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km apart")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(comparison)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(myCity.city) ↔ \(partnerCity.city)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .multilineTextAlignment(.center)

            Text("twofold")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 340)
        .background(
            LinearGradient(
                colors: [Color(hex: "1E3A5F"), Color(hex: "3E7CA6"), Color(hex: "6FBF8B")],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func avatar(_ photo: UIImage?, tint: Color) -> some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#Preview {
    NavigationStack {
        PersonalizedInsightView()
    }
    .environment({
        let model = OnboardingModel()
        model.firstName = "You"
        model.partnerName = "Erin"
        model.homeCity = Place.commonCities.first { $0.city == "Melbourne" }
        model.partnerCity = Place.commonCities.first { $0.city == "London" }
        return model
    }())
}
