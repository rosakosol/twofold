//
//  TwofoldPreviewView.swift
//  Twofold
//
//  Reflects back exactly what's been entered so far — no fabricated countdown or flight
//  when nothing was added.
//

import SwiftUI
import UIKit

struct TwofoldPreviewView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    private var trip: Trip? { appModel.upcomingTrips.first }

    private var daysToGo: Int? {
        guard let trip else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    private var selfImage: Image? {
        onboarding.selfPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    private var partnerImage: Image? {
        onboarding.partnerPhotoData.flatMap(UIImage.init(data:)).map(Image.init(uiImage:))
    }

    var body: some View {
        OnboardingScaffold(
            progress: onboarding.progress,
            title: "Your Twofold is ready ❤️",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    SectionCard {
                        HStack {
                            VStack(spacing: 6) {
                                avatarCircle(selfImage)
                                Text(onboarding.firstName.isEmpty ? "You" : onboarding.firstName).font(.headline)
                                if let city = onboarding.homeCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                            Spacer()
                            Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed)
                            Spacer()
                            VStack(spacing: 6) {
                                avatarCircle(partnerImage)
                                Text(onboarding.partnerName.isEmpty ? "Partner" : onboarding.partnerName).font(.headline)
                                if let city = onboarding.partnerCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let trip, let daysToGo {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next reunion")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.subtleInk)
                                    Text(daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go")
                                        .font(.title2.weight(.bold))
                                    if let flight = trip.flight {
                                        Text("\(flight.flightNumber) · \(trip.origin.city) → \(trip.destination.city)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SectionCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No trips yet")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Add a flight anytime to start your countdown.")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.trialTrust) }
        )
    }

    private func avatarCircle(_ image: Image?) -> some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Theme.cardBackground)
                Image(systemName: "person.fill").foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }
}

#Preview {
    NavigationStack {
        TwofoldPreviewView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
