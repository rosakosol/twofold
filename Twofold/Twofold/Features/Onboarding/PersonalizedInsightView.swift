//
//  PersonalizedInsightView.swift
//  Twofold
//
//  The distance-reveal moment — the first emotional payoff of onboarding. Staged entrance
//  animations with haptics, a fast rolling count-up of the distance, a real 2D map with
//  both partners as markers joined by a geodesic path, a real-world comparison for the
//  number, and a "Save this moment" button opening `DistanceRevealShareView` — a paged,
//  multi-layout share screen (see `DistanceShareLayout`) mirroring `GameResultsShareView`,
//  rather than a single fixed `ShareLink` snapshot.
//  Real distance/timezone math only (`Geo.distanceKm`, `Place.timeZone`), never a
//  fabricated number. Couples in the same city get adapted copy instead of an awkward
//  "0 km apart".
//

import SwiftUI
import MapKit
import UIKit

struct PersonalizedInsightView: View {
    @Environment(OnboardingModel.self) private var onboarding

    /// Drives the staged reveal: 1 = map, 2 = distance count-up, 3 = comparison line,
    /// 4 = stat tiles + buttons. Also the trigger for the per-stage haptics.
    @State private var stage = 0
    @State private var displayedKm: Double = 0
    @State private var showingShare = false
    /// Pre-fetched once per city pair via `DistanceMapView.loadMapSnapshot` — nil shows that
    /// view's own loading placeholder.
    @State private var mapSnapshot: MKMapSnapshotter.Snapshot?

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
            // Memory screens now come before the notification/Live Activity sell screens.
            primaryAction: { onboarding.path.append(.memoriesSell) }
        )
    }

    // MARK: - Distance reveal

    private func distanceReveal(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Always visible (not staged like the reveal below it) — sets the emotional tone
                // before the map/count-up animate in, the same way every other onboarding screen's
                // title is already on screen before its own staged content plays.
                Text("The distance is real!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

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
            if mapSnapshot == nil {
                mapSnapshot = await DistanceMapView.loadMapSnapshot(from: myCity.coordinate, to: partnerCity.coordinate, distanceKm: distanceKm)
            }
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

    /// The exact same globe/flat-map technique Home's own `DistanceShareCard` uses (see
    /// `DistanceMapView`'s own doc comment) — a static `MKMapSnapshotter` render, not a live
    /// interactive `Map`. Also what `DistanceSnapshotCard` (this screen's own "Save this moment"
    /// share card) renders, so the live reveal and the share card are now, deliberately, the same
    /// view.
    private func mapCard(myCity: Place, partnerCity: Place) -> some View {
        DistanceMapView(
            myCity: myCity,
            partnerCity: partnerCity,
            distanceKm: Geo.distanceKm(myCity.coordinate, partnerCity.coordinate),
            selfPhoto: onboarding.selfPhotoData.flatMap(UIImage.init(data:)),
            partnerPhoto: onboarding.partnerPhotoData.flatMap(UIImage.init(data:)),
            mapSnapshot: mapSnapshot
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom bar + snapshot

    private func bottomBar(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                // Memory screens now come before the notification/Live Activity sell screens.
                onboarding.path.append(.memoriesSell)
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .background(Theme.primaryButtonGradient, in: Capsule())
            .foregroundStyle(.white)

            Button {
                showingShare = true
            } label: {
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
        .sheet(isPresented: $showingShare) {
            DistanceRevealShareView(
                distanceKm: distanceKm,
                comparison: DistanceSnapshotCard.comparison(for: distanceKm),
                myCity: myCity,
                partnerCity: partnerCity,
                selfPhoto: onboarding.selfPhotoData.flatMap(UIImage.init(data:)),
                partnerPhoto: onboarding.partnerPhotoData.flatMap(UIImage.init(data:)),
                hoursApart: hoursApart
            )
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
