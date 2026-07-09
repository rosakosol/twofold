//
//  TwofoldPreviewView.swift
//  Twofold
//
//  Reflects back exactly what's been entered so far — no fabricated countdown or flight
//  when nothing was added.
//

import SwiftUI

struct TwofoldPreviewView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel

    private var trip: Trip? { appModel.upcomingTrips.first }

    private var daysToGo: Int? {
        guard let trip else { return nil }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    var body: some View {
        OnboardingScaffold(
            title: "Your Twofold is ready ❤️",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    SectionCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(onboarding.firstName.isEmpty ? "You" : onboarding.firstName).font(.headline)
                                if let city = onboarding.homeCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                            Spacer()
                            Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(onboarding.partnerName.isEmpty ? "Partner" : onboarding.partnerName).font(.headline)
                                if let city = onboarding.partnerCity?.city {
                                    Text(city).font(.caption).foregroundStyle(Theme.subtleInk)
                                }
                            }
                        }
                    }

                    if let trip, let daysToGo {
                        SectionCard {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        SectionCard {
                            Text("No trips yet")
                                .font(.subheadline.weight(.semibold))
                            Text("Add a flight anytime to start your countdown.")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.trialTrust) }
        )
    }
}

#Preview {
    NavigationStack {
        TwofoldPreviewView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
