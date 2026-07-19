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
            title: sameCity ? "Home is \(onboarding.homeCity?.displayCity ?? "the same city") ❤️" : "You're apart right now ❤️",
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
                    Text("\(Text(displayedKm, format: .number.precision(.fractionLength(0))).font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(Theme.skyBlue)) \(Text(MeasurementPreference.unitSuffix()).font(.title2.weight(.bold)).foregroundStyle(Theme.leafGreen))")
                    Text("apart")
                        .font(.headline)
                        .foregroundStyle(Theme.subtleInk)
                }
                .frame(maxWidth: .infinity)
                .opacity(stage >= 2 ? 1 : 0)

                Text(DistanceSnapshotCard.comparison(for: distanceKm))
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
                displayedKm = MeasurementPreference.convertedValue(km: distanceKm)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.25)) { stage = 2 }
            await rollDistance(to: MeasurementPreference.convertedValue(km: distanceKm))
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
        Map(
            initialPosition: .camera(Self.camera(containing: myCity.coordinate, partnerCity.coordinate)),
            interactionModes: []
        ) {
            Annotation(myCity.displayCity, coordinate: myCity.coordinate) {
                avatarMarker(onboarding.selfPhotoData, tint: Theme.skyBlue)
            }
            Annotation(partnerCity.displayCity, coordinate: partnerCity.coordinate) {
                avatarMarker(onboarding.partnerPhotoData, tint: Theme.heartRed)
            }
            MapPolyline(coordinates: [myCity.coordinate, partnerCity.coordinate], contourStyle: .geodesic)
                .stroke(Theme.skyBlue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
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

    /// A camera framing both cities with breathing room — set by *altitude* (`MapCamera.distance`),
    /// not by coordinate span (`MKCoordinateRegion`), which is the same fix `FlightMapView` already
    /// uses for its route-fitting and for the identical reason: `MKCoordinateRegion`-based fitting
    /// (tried first here too, several ways — see git history) silently caps how wide a region's
    /// span in *degrees* can be at a given center latitude, well short of what a genuinely distant
    /// pair can need. Oslo (60°N) and Cape Town (34°S) are ~94° of raw latitude apart; every
    /// region-based attempt topped out somewhere around 70–80° regardless of how much span or
    /// padding was requested beyond that, silently rendering a smaller, off-center crop instead
    /// that left one or both avatar markers off-screen. `MapCamera(distance:)` isn't subject to
    /// that ceiling, so it correctly zooms out for arbitrarily distant pairs, up to near-antipodal.
    private static func camera(containing a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> MapCamera {
        // Antimeridian-safe center: shift `b`'s longitude by a full turn whenever that shortens
        // the delta, so two cities straddling the 180th meridian (e.g. Auckland +174.8°, Los
        // Angeles −118.2°) resolve to the true ~67° apart the short way, not ~293° the long way.
        var bLongitude = b.longitude
        let deltaLongitude = bLongitude - a.longitude
        if deltaLongitude > 180 {
            bLongitude -= 360
        } else if deltaLongitude < -180 {
            bLongitude += 360
        }
        var centerLongitude = (a.longitude + bLongitude) / 2
        while centerLongitude > 180 { centerLongitude -= 360 }
        while centerLongitude < -180 { centerLongitude += 360 }
        let center = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: centerLongitude)

        // A generous multiple of the real point-to-point distance, floored so two very close (but
        // not identical-city) coordinates don't produce a near-zero distance that zooms in
        // absurdly. `FlightMapView` iteratively refines its own initial guess against the live
        // `MKMapView`'s actual projected pixels (`mapView.convert`) — not available from plain
        // SwiftUI `Map`, so this uses a single, more generous fixed multiplier instead of
        // iterating: comfortably enough headroom for two point markers (no route curve or label
        // capsules to clear, unlike `FlightMapView`'s case) without needing per-frame refinement.
        let distanceMeters = max(Geo.distanceKm(a, b) * 1000, 200_000)
        return MapCamera(centerCoordinate: center, distance: distanceMeters * 3.0, heading: 0, pitch: 0)
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
                    "\(MeasurementPreference.distanceLabel(km: distanceKm)) apart",
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
                comparison: DistanceSnapshotCard.comparison(for: distanceKm),
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
