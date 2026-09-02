//
//  FullTripStatsView.swift
//  Twofold
//
//  The "All Trip Stats" drill-in — every breakdown the Trip Stats summary card headlines, filtered
//  two ways that compose: what kind of trip it was, and when.
//
//  Mirrors `FullStatsView` (All Flight Stats) in shape, but not in what it filters by. Flights are
//  filtered by *who was on them*, because a flight is a thing one or both partners did. A trip's
//  meaning is in its kind — a reunion isn't the same event as a holiday together, and a solo trip
//  belongs to whoever took it — so the filter is category first, with the solo case split by
//  traveller because "Solo" alone would merge two different people's trips into one number.
//

import PostHog
import SwiftUI

struct FullTripStatsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var scope: TripScope = .all
    @State private var period: TripStatPeriod = .allTime
    @State private var expandedRankings: Set<String> = []
    @State private var sharingStat: StatCardSpec?

    /// Which trips the numbers cover.
    ///
    /// `.solo` is split by traveller rather than left as one bucket: a solo trip is one person's,
    /// and adding both partners' together produces a figure that describes neither of them.
    enum TripScope: Hashable {
        case all
        case reunion
        case together
        case soloMine
        case soloPartner
    }

    /// Deliberately not a fixed set of ranges ("last 12 months" and so on) — a travel year is the
    /// unit people think in, and the list is built from the years the couple has actually
    /// travelled. Same reasoning as `FullStatsView`'s own period picker.
    enum TripStatPeriod: Hashable {
        case allTime
        case year(Int)
    }

    private var scopedTrips: [Trip] {
        let byKind = appModel.trips.filter { trip in
            switch scope {
            case .all: true
            case .reunion: trip.category == .reunion
            case .together: trip.category == .together
            case .soloMine: trip.category == .solo && trip.travelerIDs.contains(appModel.currentUser.id)
            case .soloPartner: trip.category == .solo && trip.travelerIDs.contains(appModel.partner.id)
            }
        }
        guard case .year(let year) = period else { return byKind }
        return byKind.filter { Self.year(of: $0) == year }
    }

    /// The year a trip belongs to, by its departure — read in the device's own calendar, matching
    /// how `FullStatsView` files a flight.
    private static func year(of trip: Trip) -> Int {
        Calendar.current.component(.year, from: trip.departureDate)
    }

    /// Years the couple has actually travelled in, newest first. Built from every trip rather than
    /// the currently-scoped ones, so switching between kinds doesn't make the year you're looking
    /// at disappear out from under you.
    private var availableYears: [Int] {
        Array(Set(appModel.trips.map(Self.year))).sorted(by: >)
    }

    private var stats: TripStats { TripStats(trips: scopedTrips) }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                controls
                hero
                tripsSection
                distanceSection
                durationSection
                destinationsSection
                countriesSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Trip Stats")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Passport: Full Trip Stats")
        .sheet(item: $sharingStat) { StatShareView(stat: $0) }
    }

    // MARK: - Controls

    /// The same control All Flight Stats uses — a segmented picker, with the period menu beside it.
    ///
    /// On its own row rather than sharing one with the menu, which is the one place this departs
    /// from that screen: three segments reading "All" and two first names fit alongside a menu,
    /// five don't, and "Reunion" is the first label to become unreadable. Stacking keeps the
    /// segmented control the picker it's meant to be instead of squeezing it until the labels are
    /// useless.
    private var controls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Picker("Kind", selection: $scope) {
                Text("All").tag(TripScope.all)
                Text("Reunion").tag(TripScope.reunion)
                Text("Together").tag(TripScope.together)
                // Bare first names. "Solo · Rosa" repeated a category the segment already sits
                // beside; a name alongside Reunion and Together reads as "the trips that were
                // theirs" without needing the word.
                Text(appModel.currentUser.name).tag(TripScope.soloMine)
                Text(appModel.partner.name).tag(TripScope.soloPartner)
            }
            .pickerStyle(.segmented)

            periodMenu
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                Text("All time").tag(TripStatPeriod.allTime)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(TripStatPeriod.year(year))
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(periodLabel)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 8)
            .background(Theme.cardBackground, in: Capsule())
            .foregroundStyle(Theme.ink)
        }
    }

    private var periodLabel: String {
        switch period {
        case .allTime: "All time"
        case .year(let year): String(year)
        }
    }

    // MARK: - Sections

    private var hero: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.xs) {
                Text("\(stats.totalTrips)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(stats.totalTrips == 1 ? "trip" : "trips")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                if let top = stats.topDestination {
                    Text("Most visited: \(top.name)")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The kind breakdown is only meaningful when looking at every kind — under a single segment
    /// it would be that same number and two zeros.
    private var tripsSection: some View {
        statCard(icon: "suitcase.fill", title: "Trips", value: "\(stats.totalTrips)", unit: "total") {
            VStack(spacing: Theme.Spacing.sm) {
                if scope == .all {
                    StatBreakdownRow(label: "Reunions", value: "\(stats.reunionCount)")
                    StatBreakdownRow(label: "Together", value: "\(stats.togetherCount)")
                    StatBreakdownRow(label: "Solo", value: "\(stats.soloCount)")
                    Divider()
                }
                StatBreakdownRow(label: "Taken", value: "\(stats.pastCount)")
                StatBreakdownRow(label: "Upcoming", value: "\(stats.upcomingCount)")
            }
        }
    }

    private var distanceSection: some View {
        statCard(
            icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
            title: "Distance",
            value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm),
            unit: nil
        ) {
            StatBreakdownRow(
                label: "Average trip",
                value: MeasurementPreference.distanceLabel(km: stats.averageDistanceKm)
            )
        }
    }

    private var durationSection: some View {
        statCard(icon: "calendar", title: "Trip Days", value: "\(stats.totalDays)", unit: "days away") {
            VStack(spacing: Theme.Spacing.sm) {
                StatBreakdownRow(label: "Average trip", value: "\(stats.averageDays) days")
                StatBreakdownRow(
                    label: "Longest",
                    value: stats.longestTrip.map { "\($0.destination.displayCity) · \(RelationshipMilestoneStats.tripDuration($0))" } ?? "—"
                )
                StatBreakdownRow(
                    label: "Shortest",
                    value: stats.shortestTrip.map { "\($0.destination.displayCity) · \(RelationshipMilestoneStats.tripDuration($0))" } ?? "—"
                )
            }
        }
    }

    private var destinationsSection: some View {
        statCard(
            icon: "mappin.and.ellipse",
            title: "Top Destinations",
            value: "\(stats.destinations.count)",
            unit: "places"
        ) {
            StatRankedRows(
                title: "Top Destinations",
                ranked: stats.destinations.map { .init(name: $0.name, count: $0.count) },
                expanded: $expandedRankings
            )
        }
    }

    private var countriesSection: some View {
        statCard(
            icon: "globe.americas.fill",
            title: "Countries & Territories",
            value: "\(stats.countries.count)",
            unit: "countries"
        ) {
            StatRankedRows(
                title: "Countries & Territories",
                ranked: stats.countries.map { .init(name: $0.name, count: $0.count) },
                expanded: $expandedRankings,
                collapsedLimit: 5
            )
        }
    }

    // MARK: - Card chrome

    @ViewBuilder
    private func statCard<Rows: View>(
        icon: String,
        title: String,
        value: String,
        unit: String?,
        @ViewBuilder rows: @escaping () -> Rows
    ) -> some View {
        SectionCard {
            HStack(alignment: .top) {
                StatCardHeader(icon: icon, title: title, value: value, unit: unit)
                Spacer()
                Button {
                    sharingStat = StatCardSpec(icon: icon, title: title, value: value, unit: unit, rows: AnyView(rows()))
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }
                .accessibilityLabel("Share \(title)")
            }

            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        FullTripStatsView()
            .environment(AppModel())
    }
}
