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

import PostHog
import SwiftUI

struct PassportView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingSnapshot = false
    @State private var showingTripShare = false
    @State private var showingPassportShare = false
    @State private var showingAllFlightStats = false
    @State private var section: StatsSection = .relationship

    private enum StatsSection: String, CaseIterable {
        case relationship = "Relationship"
        case trips = "Trips"
        case flights = "Flights"
    }

    /// `FlightStatsCard`'s own scope — deliberately the current user alone, not the couple
    /// combined (that framing already lives on `RelationshipStatsCard` above it). Matches "your
    /// own travel" the way flight stats are personal, not a shared/couple figure. Scoped by each
    /// flight's own `travelerIDs` (not a linked trip's), so it's accurate regardless of whether
    /// that flight has a trip at all.
    private var flightStats: FlightStats {
        FlightStats(
            flights: appModel.flights.filter { $0.travelerIDs.contains(appModel.currentUser.id) },
            couple: appModel.couple
        )
    }

    private var relationshipStats: RelationshipMilestoneStats {
        RelationshipMilestoneStats(couple: appModel.couple, trips: appModel.trips, memories: appModel.memories)
    }

    /// Couple-wide, like `relationshipStats` above — trips are a shared activity, not a
    /// per-person document the way the flight-specific passport card is.
    private var tripStats: TripStats {
        TripStats(trips: appModel.trips)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Picker("Section", selection: $section) {
                        ForEach(StatsSection.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch section {
                    case .relationship:
                        RelationshipStatsCard(couple: appModel.couple, stats: relationshipStats) {
                            showingSnapshot = true
                        }
                    case .trips:
                        TripStatsCard(stats: tripStats) {
                            showingTripShare = true
                        }
                    case .flights:
                        FlightStatsCard(stats: flightStats, onShare: { showingPassportShare = true }, onShowAllStats: { showingAllFlightStats = true })
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Stats")
            .sheet(isPresented: $showingSnapshot) {
                RelationshipStatsShareView(couple: appModel.couple, trips: appModel.trips, memories: appModel.memories, stats: relationshipStats)
            }
            .sheet(isPresented: $showingTripShare) {
                TripStatsShareView(stats: tripStats)
            }
            .sheet(isPresented: $showingPassportShare) {
                PassportShareView(stats: flightStats)
            }
            .navigationDestination(isPresented: $showingAllFlightStats) {
                FullStatsView()
            }
        }
    }

}

// MARK: - Full stats

/// The "All Flight Stats" drill-in — every breakdown the passport card summarizes,
/// scopeable to the whole couple or either partner alone.
private struct FullStatsView: View {
    private enum StatScope: Hashable {
        case all, user, partner
    }

    @Environment(AppModel.self) private var appModel
    @Environment(\.displayScale) private var displayScale
    @State private var scope: StatScope = .all
    @State private var showAllCountries = false

    /// Scoped by each flight's own `travelerIDs` — independent of whether that flight has a
    /// linked trip, or what that trip's own (separate) `travelerIDs` says.
    private var scopedFlights: [Flight] {
        switch scope {
        case .all: appModel.flights
        case .user: appModel.flights.filter { $0.travelerIDs.contains(appModel.currentUser.id) }
        case .partner: appModel.flights.filter { $0.travelerIDs.contains(appModel.partner.id) }
        }
    }

    private var stats: FlightStats {
        FlightStats(flights: scopedFlights, couple: appModel.couple)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                Picker("Who", selection: $scope) {
                    Text("All").tag(StatScope.all)
                    Text(appModel.currentUser.name).tag(StatScope.user)
                    Text(appModel.partner.name).tag(StatScope.partner)
                }
                .pickerStyle(.segmented)

                hero
                flightsSection
                distanceSection
                timeSection
                rankedSection(
                    title: "Top Visited Airports",
                    total: stats.airports.count,
                    unit: "total airports",
                    ranked: stats.airports
                )
                airlinesSection
                rankedSection(
                    title: "Top Routes",
                    total: stats.routes.count,
                    unit: "total routes",
                    ranked: stats.routes
                )
                countriesSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Flight Stats")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Passport: Full Stats")
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
                .foregroundStyle(Theme.subtleInk)

            // Flight-based (same figure as `distanceSection` below), not trip/reunion-based — a
            // tracked flight should count toward "how far you've travelled" whether or not it's
            // linked to a Trip at all (most aren't; see `FlightStats.init`'s own comment).
            Text("\(Text(MeasurementPreference.convertedValue(km: stats.totalDistanceKm), format: .number.precision(.fractionLength(0))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlue))\(Text(" \(MeasurementPreference.unitSuffix())").font(.title.weight(.bold)).foregroundStyle(Theme.leafGreen))")

            if scope == .all {
                Text(appModel.couple.sharesHomeCity ? "together" : "for each other")
                    .font(.headline)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: Sections

    private var flightsSection: some View {
        shareableCard(title: "Flights", value: "\(stats.flightCount)", unit: "total") {
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
            title: "Flight Distance",
            value: Int(MeasurementPreference.convertedValue(km: stats.totalDistanceKm).rounded()).formatted(),
            unit: MeasurementPreference.unitSuffix()
        ) {
            Text("Average distance: \(MeasurementPreference.distanceLabel(km: stats.averageDistanceKm))")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)

            VStack(spacing: Theme.Spacing.md) {
                multipleRow(emoji: "🌍", value: stats.earthMultiple, precision: 1, label: "Around the Earth")
                multipleRow(emoji: "🌕", value: stats.moonMultiple, precision: 2, label: "To the Moon")
                multipleRow(emoji: "☀️", value: stats.sunMultiple, precision: 3, label: "Around the Sun")
            }
        }
    }

    private var timeSection: some View {
        shareableCard(title: "Flight Time", value: FlightStats.duration(stats.totalFlightTime), unit: nil) {
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
        shareableCard(title: "Top Airlines", value: "\(stats.airlines.count)", unit: "total airlines") {
            if !stats.airlines.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(stats.airlines.prefix(3)) { entry in
                        airlineRow(entry)
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
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Text("×\(entry.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func rankedSection(title: String, total: Int, unit: String, ranked: [FlightStats.Ranked]) -> some View {
        shareableCard(title: title, value: "\(total)", unit: unit) {
            if !ranked.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(ranked.prefix(3)) { entry in
                        breakdownRow(label: entry.name, value: "×\(entry.count)")
                    }
                }
            }
        }
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

    /// Unlike the other `rankedSection`s (always top-3), the country list shows up to 5 with a
    /// "Show more" toggle, plus a fixed 3x3 region grid underneath — countries are the one
    /// breakdown worth seeing in full, not just a top-N taste.
    private var countriesSection: some View {
        shareableCard(title: "Countries & Territories", value: "\(stats.countries.count)", unit: "total") {
            if !stats.countries.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(stats.countries.prefix(showAllCountries ? stats.countries.count : 5)) { entry in
                        breakdownRow(label: entry.name, value: "×\(entry.count)")
                    }
                    if stats.countries.count > 5 {
                        Button(showAllCountries ? "Show less" : "Show more") {
                            withAnimation { showAllCountries.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.skyBlue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

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
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? Theme.ink : Theme.subtleInk.opacity(0.4))
            Text(region.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
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

    /// A stats card with a share button in its header — the shared image re-renders the same
    /// header and rows (minus the button) on the app background, with a small brand mark.
    private func shareableCard<Rows: View>(
        title: String,
        value: String,
        unit: String?,
        @ViewBuilder rows: @escaping () -> Rows
    ) -> some View {
        SectionCard {
            HStack(alignment: .top) {
                sectionHeader(title: title, value: value, unit: unit)
                Spacer()
                ShareLink(
                    item: renderedCard(title: title, value: value, unit: unit, rows: rows),
                    preview: SharePreview(title, image: renderedCard(title: title, value: value, unit: unit, rows: rows))
                ) {
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

    /// Matches `SnapshotThemeCard`'s format exactly (brand mark up top, single rounded gradient
    /// card, same corner radius/width) so every image Twofold generates — the Snapshot card and
    /// each individual Full Flight Stats card — reads as the same shareable format.
    @MainActor
    private func renderedCard<Rows: View>(
        title: String,
        value: String,
        unit: String?,
        @ViewBuilder rows: () -> Rows
    ) -> Image {
        let card = VStack(spacing: Theme.Spacing.lg) {
            TwofoldBrandMark(color: Theme.ink, size: 28, textStyle: .title3)
                .padding(.top, Theme.Spacing.lg)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionHeader(title: title, value: value, unit: unit)
                rows()
            }
            .padding(.bottom, Theme.Spacing.lg)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(width: 360)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

        let renderer = ImageRenderer(content: card)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }

    private func sectionHeader(title: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("\(Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlue))\(Text(unit.map { " \($0)" } ?? "").font(.title3.weight(.semibold)).foregroundStyle(Theme.subtleInk))")
        }
    }

    private func breakdownRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }

    private func multipleRow(emoji: String, value: Double, precision: Int, label: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(emoji)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                    Spacer()
                    Text("\(value.formatted(.number.precision(.fractionLength(precision))))x")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
                // Progress toward one full multiple (one lap of Earth, one Moon trip, …),
                // full once the multiple passes 1.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.subtleInk.opacity(0.15))
                        Capsule()
                            .fill(Theme.skyBlue)
                            .frame(width: geo.size.width * min(max(value, 0), 1))
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

// MARK: - Flight stats math

/// Everything the passport card, snapshot card, and full-stats page show, computed from real
/// tracked flights — a flight counts here whether or not it has a linked trip (see `init`'s own
/// doc comment for exactly which fields need a trip anyway, and why).
struct FlightStats {
    struct Ranked: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    let flightCount: Int
    let userFlightCount: Int
    let partnerFlightCount: Int
    let domesticCount: Int
    let internationalCount: Int
    let longHaulCount: Int
    let shortHaulCount: Int
    let totalDistanceKm: Double
    let averageDistanceKm: Double
    let totalFlightTime: TimeInterval
    let averageFlightTime: TimeInterval
    let longestFlightTime: TimeInterval
    /// e.g. "LAX-MEL" — the specific flight behind `longestFlightTime`, in that flight's own
    /// origin→destination order (unlike `routes` below, which is direction-agnostic for
    /// counting purposes). Nil only when no flight has a resolvable departure/arrival pair.
    let longestFlightRoute: String?
    let airports: [Ranked]
    let airlines: [Ranked]
    let routes: [Ranked]
    let countries: [Ranked]

    var earthMultiple: Double { totalDistanceKm / Geo.earthCircumferenceKm }
    var moonMultiple: Double { totalDistanceKm / Geo.moonDistanceKm }
    var sunMultiple: Double { totalDistanceKm / Geo.sunCircumferenceKm }

    /// Flights longer than this count as long haul.
    private static let longHaulKm = 4_000.0

    /// Every stat here — including domestic/international/countries — is computed straight from
    /// `flights` alone, whether or not any of them are linked to a Trip. Country comes from each
    /// flight's own `FlightAirport.country`, resolved server-side against the `airports`
    /// reference table when the flight was tracked (see add-flight/index.ts) — never from a
    /// linked trip's `Place`. A flight whose airport(s) aren't in that reference table (rare)
    /// just doesn't contribute to these three breakdowns; every other stat below still counts it.
    init(flights: [Flight], couple: Couple) {
        flightCount = flights.count
        userFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerA.id) }
        partnerFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerB.id) }

        let flightCountries = flights.compactMap { flight -> (String, String)? in
            guard let origin = flight.origin.country, let destination = flight.destination.country else { return nil }
            return (origin, destination)
        }
        domesticCount = flightCountries.count { $0.0 == $0.1 }
        internationalCount = flightCountries.count { $0.0 != $0.1 }
        countries = Self.ranked(flightCountries.flatMap { [$0.0, $0.1] })

        // Each flight's own great-circle distance, not a trip's `effectiveDistanceKm` — "long
        // haul" is naturally about a single flight, and a standalone long flight with no trip
        // attached obviously still qualifies.
        let flightDistances = flights.compactMap { flight -> Double? in
            guard let origin = flight.origin.coordinate, let destination = flight.destination.coordinate else { return nil }
            return Geo.distanceKm(origin, destination)
        }
        longHaulCount = flightDistances.count { $0 > Self.longHaulKm }
        shortHaulCount = flightDistances.count { $0 <= Self.longHaulKm }
        totalDistanceKm = flightDistances.reduce(0, +)
        averageDistanceKm = flightDistances.isEmpty ? 0 : totalDistanceKm / Double(flightDistances.count)

        // From each flight's own scheduled/actual times — a trip's `departureDate`/`arrivalDate`
        // span the whole vacation (e.g. a 14-day trip), not how long any single flight was
        // actually in the air, which is what "Flight time" is supposed to mean.
        let durations = flights.compactMap { flight -> (time: TimeInterval, route: String)? in
            guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else { return nil }
            return (arrival.timeIntervalSince(departure), "\(flight.origin.displayCode)-\(flight.destination.displayCode)")
        }
        totalFlightTime = durations.map(\.time).reduce(0, +)
        averageFlightTime = durations.isEmpty ? 0 : totalFlightTime / Double(durations.count)
        let longest = durations.max { $0.time < $1.time }
        longestFlightTime = longest?.time ?? 0
        longestFlightRoute = longest?.route

        airports = Self.ranked(flights.flatMap { [$0.origin.displayCode, $0.destination.displayCode] })
        airlines = Self.ranked(flights.compactMap { flight -> String? in
            let code = flight.flightNumber.prefix { $0.isLetter }
            return code.isEmpty ? nil : code.uppercased()
        })
        // Direction-agnostic, so MEL → SIN and SIN → MEL count as one route.
        routes = Self.ranked(flights.map { [$0.origin.displayCode, $0.destination.displayCode].sorted().joined(separator: " – ") })
    }

    private static func ranked(_ names: [String]) -> [Ranked] {
        Dictionary(grouping: names, by: { $0 })
            .map { Ranked(name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

#Preview {
    PassportView()
        .environment(AppModel())
}
