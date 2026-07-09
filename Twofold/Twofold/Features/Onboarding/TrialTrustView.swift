//
//  TrialTrustView.swift
//  Twofold
//

import SwiftUI

struct TrialTrustView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var shownPoints: Set<Int> = []

    private let points = [
        "No payment due today",
        "Full access for 14 days",
        "Cancel anytime",
    ]

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: "We want you to try Twofold for free",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    if let homeCity = onboarding.homeCity, let partnerCity = onboarding.partnerCity {
                        globeCard(homeCity: homeCity, partnerCity: partnerCity)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.leafGreen)
                                Text(point)
                                    .font(.subheadline.weight(.medium))
                            }
                            .opacity(shownPoints.contains(index) ? 1 : 0)
                            .offset(x: shownPoints.contains(index) ? 0 : -16)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .onAppear {
                        for index in points.indices {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.15 + Double(index) * 0.15)) {
                                shownPoints.insert(index)
                            }
                        }
                    }

                    Text("We'll remind you before your free trial ends.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            },
            primaryTitle: "Continue for free",
            primaryAction: { onboarding.path.append(.saveAccount) }
        )
    }

    /// Reuses the real `RelationshipGlobeView` (the same 3D MapKit globe shown in-app) with
    /// `animatesPath: true` so the route between the two of you pulses gently, rather than
    /// building a separate onboarding-only globe visual.
    private func globeCard(homeCity: Place, partnerCity: Place) -> some View {
        let couple = Couple(
            partnerA: Person(
                name: onboarding.firstName.isEmpty ? "You" : onboarding.firstName,
                homeCity: homeCity,
                accentColor: Person.palette[1],
                avatarURL: tempImageURL(for: onboarding.selfPhotoData, name: "onboarding-self-preview")
            ),
            partnerB: Person(
                name: onboarding.partnerName,
                homeCity: partnerCity,
                accentColor: Person.palette[0],
                avatarURL: tempImageURL(for: onboarding.partnerPhotoData, name: "onboarding-partner-preview")
            ),
            startedDatingOn: .now
        )
        let trip = Trip(
            travelerID: couple.partnerB.id,
            origin: partnerCity,
            destination: homeCity,
            departureDate: .now,
            arrivalDate: .now.addingTimeInterval(8 * 3600),
            category: .seeingEachOther,
            distanceKm: Geo.distanceKm(partnerCity.coordinate, homeCity.coordinate)
        )

        return RelationshipGlobeView(couple: couple, partnerACity: homeCity, partnerBCity: partnerCity, activeTrip: trip, animatesPath: true)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// `AvatarView` loads from a URL via `AsyncImage`, which also works for local `file://`
    /// URLs — so a picked-but-not-yet-uploaded onboarding photo can still show on the globe
    /// without needing a real signed-in session to upload against yet.
    private func tempImageURL(for data: Data?, name: String) -> URL? {
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).jpg")
        try? data.write(to: url)
        return url
    }
}

#Preview {
    NavigationStack {
        TrialTrustView()
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
