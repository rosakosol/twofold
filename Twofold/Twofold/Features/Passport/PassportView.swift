//
//  PassportView.swift
//  Twofold
//
//  The "Stats" tab (still `MainTab.passport` internally) — three sections via the segmented
//  control: Relationship (days together, trips, memories, milestones), Trips (couple-wide trip
//  breakdown), and Flights (`FlightStatsCard`, the current user's own tracked-flight numbers).
//  "All Flight Stats" drills into the full flight breakdown (scoped All / user / partner via a
//  segmented control) — every card there individually shareable as an image. All computed from
//  real trips, never fabricated.
//

import SwiftUI

/// Which of the Stats screen's three cards is showing. Top-level rather than private to
/// `PassportView` so a widget deep link can name one — the Days Together widget lands on the
/// relationship card specifically, not just the tab.
enum StatsSection: String, CaseIterable {
    case relationship = "Relationship"
    case trips = "Trips"
    case flights = "Flights"
}

struct PassportView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingSnapshot = false
    @State private var showingTripShare = false
    @State private var showingPassportShare = false
    @State private var showingAllFlightStats = false
    @State private var showingAllTripStats = false
    /// Set by a widget deep link that named a card. Consumed (and cleared) on arrival, so it
    /// steers this screen once rather than pinning it — the picker still works normally after.
    @Binding var requestedSection: StatsSection?

    @State private var section: StatsSection = .relationship


    /// `FlightStatsCard`'s own scope — deliberately the current user alone, not the couple
    /// combined (that framing already lives on `RelationshipStatsCard` above it). Matches "your
    /// own travel" the way flight stats are personal, not a shared/couple figure. Scoped by each
    /// flight's own `travelerIDs` (not a linked trip's), so it's accurate regardless of whether
    /// that flight has a trip at all.
    private var flightStats: FlightStats {
        FlightStats(
            flights: appModel.travel.flights.filter { $0.travelerIDs.contains(appModel.currentUser.id) },
            couple: appModel.session.couple
        )
    }

    private var relationshipStats: RelationshipMilestoneStats {
        RelationshipMilestoneStats(couple: appModel.session.couple, trips: appModel.travel.trips, memories: appModel.travel.memories)
    }

    /// Couple-wide, like `relationshipStats` above — trips are a shared activity, not a
    /// per-person document the way the flight-specific passport card is.
    private var tripStats: TripStats {
        TripStats(trips: appModel.travel.trips)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    TwofoldSegmentedControl(selection: $section, accessibilityLabel: "Section")

                    switch section {
                    case .relationship:
                        RelationshipStatsCard(couple: appModel.session.couple, stats: relationshipStats) {
                            showingSnapshot = true
                        }
                    case .trips:
                        TripStatsCard(
                            stats: tripStats,
                            onShare: { showingTripShare = true },
                            onShowAllStats: { showingAllTripStats = true }
                        )
                    case .flights:
                        FlightStatsCard(stats: flightStats, onShare: { showingPassportShare = true }, onShowAllStats: { showingAllFlightStats = true })
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(ScreenBackground())
            .refreshable { await appModel.refreshAll() }
            .navigationTitle("Stats")
            .onChange(of: requestedSection) { _, requested in
                guard let requested else { return }
                section = requested
                requestedSection = nil
            }
            .onAppear {
                // Also on appear: a deep link can set this before this view exists, in which case
                // `onChange` never fires for it.
                if let requestedSection {
                    section = requestedSection
                    self.requestedSection = nil
                }
            }
            .sheet(isPresented: $showingSnapshot) {
                RelationshipStatsShareView(couple: appModel.session.couple, stats: relationshipStats)
            }
            .sheet(isPresented: $showingTripShare) {
                TripStatsShareView(stats: tripStats)
            }
            .sheet(isPresented: $showingPassportShare) {
                PassportShareView(stats: flightStats)
            }
            .navigationDestination(isPresented: $showingAllTripStats) {
                FullTripStatsView()
            }
            .navigationDestination(isPresented: $showingAllFlightStats) {
                FullStatsView()
            }
        }
    }

}

#Preview {
    PassportView(requestedSection: .constant(nil))
        .environment(AppModel())
}
