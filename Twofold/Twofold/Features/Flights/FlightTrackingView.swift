//
//  FlightTrackingView.swift
//  Twofold
//

import SwiftUI

struct FlightTrackingView: View {
    let trip: Trip
    @State private var notifyOnLanding = true

    private var flight: Flight? { trip.flight }

    private var timeRemainingLabel: String {
        guard let flight else { return "" }
        let hours = Int(flight.timeRemaining) / 3600
        let minutes = (Int(flight.timeRemaining) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(flight?.status.emotionalHeadline ?? "On the way")
                        .font(.title2.weight(.bold))
                    if let flight {
                        Text("\(flight.flightNumber) · \(flight.origin.city) to \(flight.destination.city)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .frame(maxWidth: .infinity)

                SectionCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Landing in")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                        Text(timeRemainingLabel)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        if let flight {
                            Text(flight.scheduledArrival, format: .dateTime.hour().minute())
                                .font(.subheadline)
                                .foregroundStyle(Theme.subtleInk)
                        }

                        HStack {
                            Image(systemName: "airplane")
                                .font(.title2)
                                .foregroundStyle(Theme.skyBlue)
                            Spacer()
                        }
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Theme.skyBlue.opacity(0.2))
                                    .frame(height: 4)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(Theme.skyBlue)
                                            .frame(width: proxy.size.width * (flight?.progress ?? 0), height: 4)
                                    }
                            }
                            .frame(height: 4)
                            .padding(.top, 18)
                        }

                        HStack {
                            Text(trip.origin.iataCode ?? trip.origin.city)
                            Spacer()
                            Text(trip.destination.iataCode ?? trip.destination.city)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let flight {
                    SectionCard {
                        ForEach(Array(flight.timeline.enumerated()), id: \.element.id) { index, event in
                            TimelineRow(event: event, isLast: index == flight.timeline.count - 1)
                        }
                    }
                }

                SectionCard {
                    Toggle("Get notified when they land", isOn: $notifyOnLanding)
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("\(MockData.dara.name)'s journey")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FlightTrackingView(trip: MockData.reunionTrip)
    }
}
