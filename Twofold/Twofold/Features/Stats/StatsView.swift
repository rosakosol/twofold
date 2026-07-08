//
//  StatsView.swift
//  Twofold
//

import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingSnapshot = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        Text("Our journey")
                            .font(.title3)
                            .foregroundStyle(Theme.subtleInk)

                        Text("You've travelled")
                            .font(.headline)
                            .foregroundStyle(Theme.subtleInk)

                        (Text(appModel.stats.totalDistanceKm, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.skyBlue)
                        + Text(" km")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Theme.leafGreen))

                        Text("for each other")
                            .font(.headline)
                            .foregroundStyle(Theme.subtleInk)

                        Text("That's \(appModel.stats.earthMultiple, format: .number.precision(.fractionLength(1))) times around the Earth 🌍")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.lg)

                    SectionCard {
                        HStack {
                            StatTile(icon: "airplane", value: "\(appModel.stats.tripCount)", label: "Trips")
                            StatTile(icon: "ticket.fill", value: "\(appModel.stats.flightCount)", label: "Flights", tint: Theme.skyBlue)
                            StatTile(icon: "globe.americas.fill", value: "\(appModel.stats.countryCount)", label: "Countries", tint: Theme.leafGreen)
                        }

                        Divider()

                        HStack {
                            StatTile(icon: "heart.fill", value: "\(appModel.stats.daysTogether)", label: "Days together", tint: Theme.heartRed)
                            StatTile(icon: "globe", value: "\(appModel.stats.earthMultiple.formatted(.number.precision(.fractionLength(1))))x", label: "Around Earth", tint: Theme.leafGreen)
                        }
                    }

                    Button {
                        showingSnapshot = true
                    } label: {
                        Label("Create a snapshot", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.skyBlue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Stats")
            .sheet(isPresented: $showingSnapshot) {
                SnapshotShareView()
            }
        }
    }
}

#Preview {
    StatsView()
        .environment(AppModel())
}
