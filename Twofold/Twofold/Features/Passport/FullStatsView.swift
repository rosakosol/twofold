//
//  FullStatsView.swift
//  Twofold
//
//  The "All Flight Stats" drill-in from the Stats tab's Flights card.
//

import PostHog
import SwiftUI

/// The "All Flight Stats" drill-in — every breakdown the passport card summarizes,
/// scopeable to the whole couple or either partner alone.
struct FullStatsView: View {
    private enum StatScope: Hashable {
        case all, user, partner
    }

    /// Which slice of time the numbers cover. Deliberately not an enum of fixed ranges ("last 12
    /// months" and so on) — a travel year is the unit people actually think in, and the list is
    /// built from the years the couple has actually flown rather than a calendar.
    private enum StatPeriod: Hashable {
        case allTime
        case year(Int)

        var label: String {
            switch self {
            case .allTime: "All time"
            case .year(let year): String(year)
            }
        }
    }

    @Environment(AppModel.self) private var appModel
    @State private var scope: StatScope = .all
    @State private var period: StatPeriod = .allTime
    /// Which ranked cards have been expanded past their first few rows, keyed by card title.
    ///
    /// Each card headlines a count of everything and then listed only the top three, with nothing
    /// saying so — "22" above three airports reads as a number that can't be right, rather than as
    /// three of twenty-two. Reported exactly that way.
    @State private var expandedRankings: Set<String> = []
    /// Set by a section's share button (see `shareableCard`) to open that section's own
    /// full-screen preview — the same "see the card before you send it" flow `PassportShareView`
    /// already gives the summary Flight Stats card, rather than firing a `ShareLink` straight to
    /// the system sheet with no preview.
    @State private var sharingStat: StatCardSpec?

    /// Scoped by each flight's own `travelerIDs` — independent of whether that flight has a
    /// linked trip, or what that trip's own (separate) `travelerIDs` says.
    private var scopedFlights: [Flight] {
        let byPerson: [Flight]
        switch scope {
        case .all: byPerson = appModel.flights
        case .user: byPerson = appModel.flights.filter { $0.travelerIDs.contains(appModel.currentUser.id) }
        case .partner: byPerson = appModel.flights.filter { $0.travelerIDs.contains(appModel.partner.id) }
        }
        guard case .year(let year) = period else { return byPerson }
        return byPerson.filter { Self.year(of: $0) == year }
    }

    /// The year a flight belongs to, by its departure. Nil for a flight with no usable departure
    /// time, which then belongs to no year and only ever appears under All time — better than
    /// silently filing it under whichever year happens to be selected.
    ///
    /// Read in the device's own calendar rather than the departure airport's: a flight leaving late
    /// on 31 December is a rounding case either way, and using the traveller's own calendar at
    /// least matches the year they'd say they took it in.
    private static func year(of flight: Flight) -> Int? {
        flight.bestDeparture.map { Calendar.current.component(.year, from: $0) }
    }

    /// Years the couple has actually flown in, newest first. Built from every flight rather than
    /// the currently-scoped ones, so switching between All and a partner doesn't make the year
    /// you're looking at disappear out from under you.
    private var availableYears: [Int] {
        Array(Set(appModel.flights.filter(\.hasBeenFlown).compactMap(Self.year))).sorted(by: >)
    }

    private var stats: FlightStats {
        FlightStats(flights: scopedFlights, couple: appModel.couple)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Who above, when below and trailing — two independent filters that compose, so
                // they still read as one control strip.
                //
                // Stacked rather than sharing a row, matching `FullTripStatsView`. Sharing one row
                // meant the segments and the menu competed for the same width: three segments, two
                // of them first names, squeezed a little thinner with every character in a longer
                // name. Full width gives the names room, and the menu keeps its trailing position
                // on the row beneath.
                VStack(spacing: Theme.Spacing.sm) {
                    TwofoldSegmentedControl(
                        selection: $scope,
                        options: [(StatScope.all, "All"), (StatScope.user, appModel.currentUser.name), (StatScope.partner, appModel.partner.name)],
                        accessibilityLabel: "Who"
                    )

                    periodMenu
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                hero
                flightsSection
                distanceSection
                timeSection
                rankedSection(
                    icon: "building.2.fill",
                    title: "Top visited airports",
                    total: stats.airports.count,
                    // "different", not "total". These have always been counts of distinct things —
                    // `ranked` groups by name — but captioning a 3 as "total airports" reads as
                    // every visit added up, so a correct number looked wrong.
                    unit: "airports",
                    ranked: stats.airports
                )
                airlinesSection
                rankedSection(
                    icon: "arrow.triangle.swap",
                    title: "Top routes",
                    total: stats.routes.count,
                    unit: "routes",
                    ranked: stats.routes
                )
                countriesSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(ScreenBackground())
        .navigationTitle("Flight stats")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Passport: Full Stats")
        .sheet(item: $sharingStat) { stat in
            StatShareView(stat: stat)
        }
    }

    /// A menu rather than more segments: the year list grows without bound, and segments would
    /// squeeze the names above them thinner every year the couple flies.
    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                Text("All time").tag(StatPeriod.allTime)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(StatPeriod.year(year))
                }
            }
        } label: {
            FilterChip(text: period.label, icon: "calendar")
        }
        .accessibilityLabel("Time period")
        .accessibilityValue(period.label)
    }

    private var heroName: String {
        switch scope {
        case .all: "You've"
        case .user: "\(appModel.currentUser.name) has"
        case .partner: "\(appModel.partner.name) has"
        }
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text("\(heroName) travelled")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            // Flight-based (same figure as `distanceSection` below), not trip/reunion-based — a
            // tracked flight should count toward "how far you've travelled" whether or not it's
            // linked to a Trip at all (most aren't; see `FlightStats.init`'s own comment).
            Text("\(Text(MeasurementPreference.convertedValue(km: stats.totalDistanceKm), format: .number.precision(.fractionLength(0))).font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.accent))\(Text(" \(MeasurementPreference.unitSuffix())").font(.title.weight(.bold)).foregroundStyle(Theme.success))")

            if scope == .all {
                Text(appModel.couple.sharesHomeCity ? "together" : "for each other")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }

            // Without this the headline number silently changes meaning when a year is picked —
            // the same big figure, now covering a slice, with nothing on screen saying which.
            if case .year(let year) = period {
                Text("in \(String(year))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: Sections

    private var flightsSection: some View {
        shareableCard(icon: "airplane", title: "Flights", value: "\(stats.flightCount)", unit: "total") {
            VStack(spacing: Theme.Spacing.sm) {
                // Per-partner split only makes sense when looking at the couple as a whole.
                if scope == .all {
                    breakdownRow(label: appModel.currentUser.name, value: "\(stats.userFlightCount)")
                    breakdownRow(label: appModel.partner.name, value: "\(stats.partnerFlightCount)")
                    Divider()
                }
                breakdownRow(label: "Domestic", value: "\(stats.domesticCount)")
                breakdownRow(label: "International", value: "\(stats.internationalCount)")
                breakdownRow(label: "Short haul", value: "\(stats.shortHaulCount)")
                breakdownRow(label: "Long haul", value: "\(stats.longHaulCount)")
            }
        }
    }

    private var distanceSection: some View {
        shareableCard(
            icon: "ruler.fill",
            title: "Flight distance",
            value: Int(MeasurementPreference.convertedValue(km: stats.totalDistanceKm).rounded()).formatted(),
            unit: MeasurementPreference.unitSuffix()
        ) {
            Text("Average distance: \(MeasurementPreference.distanceLabel(km: stats.averageDistanceKm))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: Theme.Spacing.md) {
                multipleRow(emoji: "🌍", value: stats.earthMultiple, precision: 1, label: "Around the Earth")
                multipleRow(emoji: "🌕", value: stats.moonMultiple, precision: 2, label: "To the Moon")
                multipleRow(emoji: "☀️", value: stats.sunMultiple, precision: 3, label: "Around the Sun")
            }
        }
    }

    private var timeSection: some View {
        shareableCard(icon: "clock.fill", title: "Flight time", value: FlightStats.duration(stats.totalFlightTime), unit: nil) {
            VStack(spacing: Theme.Spacing.sm) {
                breakdownRow(label: "Avg. flight time", value: FlightStats.duration(stats.averageFlightTime))
                breakdownRow(
                    label: "Longest flight",
                    value: stats.longestFlightRoute.map { "\($0) · \(FlightStats.duration(stats.longestFlightTime))" }
                        ?? FlightStats.duration(stats.longestFlightTime)
                )
            }
        }
    }

    /// Unlike the other `rankedSection`s, each row here carries the operator's own tailfin logo
    /// (`entry.name` is already the IATA/operator code `FlightStats` extracted from the flight
    /// number prefix) — same `AirlineLogoView`/`AirlineLogo.url(forIATACode:)` pairing
    /// `FlightTrackingView`'s header uses, just keyed off the ranked code instead of a live flight.
    private var airlinesSection: some View {
        shareableCard(icon: "airplane.circle.fill", title: "Top airlines", value: "\(stats.airlines.count)", unit: "airlines") {
            if !stats.airlines.isEmpty {
                let isExpanded = expandedRankings.contains("Top airlines")
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(stats.airlines.prefix(isExpanded ? stats.airlines.count : 3)) { entry in
                        airlineRow(entry)
                    }
                    if stats.airlines.count > 3 {
                        Button(isExpanded ? "Show less" : "Show all \(stats.airlines.count)") {
                            withAnimation {
                                if isExpanded { expandedRankings.remove("Top airlines") } else { expandedRankings.insert("Top airlines") }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func airlineRow(_ entry: FlightStats.Ranked) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            AirlineLogoView(url: AirlineLogo.url(forIATACode: entry.name), size: 22)
            Text(entry.name)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Text("×\(entry.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func rankedSection(icon: String, title: String, total: Int, unit: String, ranked: [FlightStats.Ranked]) -> some View {
        shareableCard(icon: icon, title: title, value: "\(total)", unit: unit) {
            if !ranked.isEmpty {
                rankedRows(title: title, ranked: ranked)
            }
        }
    }

    /// The card's first few entries, with a way to reach the rest — see `StatRankedRows`,
    /// which `FullTripStatsView` shares.
    private func rankedRows(title: String, ranked: [FlightStats.Ranked], collapsedLimit: Int = 3) -> some View {
        StatRankedRows(
            title: title,
            ranked: ranked.map { .init(name: $0.name, count: $0.count) },
            expanded: $expandedRankings,
            collapsedLimit: collapsedLimit
        )
    }

    /// Number of distinct countries visited per `CountryRegion` — always all nine regions, in
    /// `CountryRegion.allCases`'s order, zero-filled for a region with nothing visited yet so the
    /// grid below never reflows around a missing tile.
    private var regionCounts: [(region: CountryRegion, count: Int)] {
        var counts: [CountryRegion: Int] = [:]
        for country in stats.countries {
            guard let region = CountryRegion.region(for: country.name) else { continue }
            counts[region, default: 0] += 1
        }
        return CountryRegion.allCases.map { ($0, counts[$0] ?? 0) }
    }

    /// Shows 5 before collapsing rather than the other cards' 3, plus a fixed 3x3 region grid
    /// underneath — countries are the one breakdown worth seeing more of at a glance.
    private var countriesSection: some View {
        shareableCard(icon: "globe.americas.fill", title: "Countries & territories", value: "\(stats.countries.count)", unit: "countries") {
            if !stats.countries.isEmpty {
                rankedRows(title: "Countries & territories", ranked: stats.countries, collapsedLimit: 5)

                Divider()

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3), spacing: Theme.Spacing.sm) {
                    ForEach(regionCounts, id: \.region) { entry in
                        regionTile(region: entry.region, count: entry.count)
                    }
                }
            }
        }
    }

    private func regionTile(region: CountryRegion, count: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(count)x")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(count > 0 ? Theme.textPrimary : Theme.textSecondary)
            Text(region.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .themedCardBackground(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: Card scaffolding + sharing

    /// A stats card with a share button in its header — icon + title mirror `FlightStatsCard`'s
    /// own header row exactly, so this reads as the same card family. The share button doesn't
    /// fire a `ShareLink` directly; it opens `StatShareView`, the same "see the card before you
    /// send it" preview screen `PassportShareView` gives the summary Flight Stats card.
    private func shareableCard<Rows: View>(
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
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("Share \(title)")
            }

            rows()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(label: String, value: String) -> some View {
        StatBreakdownRow(label: label, value: value)
    }

    private func multipleRow(emoji: String, value: Double, precision: Int, label: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(emoji)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(value.formatted(.number.precision(.fractionLength(precision))))x")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                }
                // Progress toward one full multiple (one lap of Earth, one Moon trip, …),
                // full once the multiple passes 1.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.textSecondary.opacity(0.15))
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * min(max(value, 0), 1))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}
