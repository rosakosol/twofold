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
            trips: appModel.trips,
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

    /// Only for `hero`'s reunion-distance figure below, which is genuinely a trip-level concept
    /// ("reunion trip") — `stats` itself is scoped by `scopedFlights`, not this.
    private var scopedTrips: [Trip] {
        switch scope {
        case .all: appModel.trips
        case .user: appModel.trips.filter { $0.travelerIDs.contains(appModel.currentUser.id) }
        case .partner: appModel.trips.filter { $0.travelerIDs.contains(appModel.partner.id) }
        }
    }

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
        FlightStats(flights: scopedFlights, trips: appModel.trips, couple: appModel.couple)
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
                rankedSection(
                    title: "Top Airlines",
                    total: stats.airlines.count,
                    unit: "total airlines",
                    ranked: stats.airlines
                )
                rankedSection(
                    title: "Top Routes",
                    total: stats.routes.count,
                    unit: "total routes",
                    ranked: stats.routes
                )
                rankedSection(
                    title: "Countries & Territories",
                    total: stats.countries.count,
                    unit: "total",
                    ranked: stats.countries
                )
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

            // Reunion-only, same as AppModel.stats.totalDistanceKm — see that property's comment.
            // Kept reunion-scoped across all three Who tabs (not just "All"), so switching scope
            // only changes *whose* reunion travel is being measured, never what's being measured.
            // `effectiveDistanceKm`, not the raw `distanceKm`, so a connecting itinerary's real
            // flown distance counts.
            Text("\(Text(MeasurementPreference.convertedValue(km: scopedTrips.filter { $0.isReunionTrip }.reduce(0) { $0 + $1.effectiveDistanceKm }), format: .number.precision(.fractionLength(0))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlue))\(Text(" \(MeasurementPreference.unitSuffix())").font(.title.weight(.bold)).foregroundStyle(Theme.leafGreen))")

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
                breakdownRow(label: "Longest flight", value: FlightStats.duration(stats.longestFlightTime))
            }
        }
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
    let totalDistanceKm: Double
    let averageDistanceKm: Double
    let totalFlightTime: TimeInterval
    let averageFlightTime: TimeInterval
    let longestFlightTime: TimeInterval
    let airports: [Ranked]
    let airlines: [Ranked]
    let routes: [Ranked]
    let countries: [Ranked]

    var earthMultiple: Double { totalDistanceKm / Geo.earthCircumferenceKm }
    var moonMultiple: Double { totalDistanceKm / Geo.moonDistanceKm }
    var sunMultiple: Double { totalDistanceKm / Geo.sunCircumferenceKm }

    /// Flights longer than this count as long haul.
    private static let longHaulKm = 4_000.0

    /// `flights` drives every stat except domestic/international/countries — a tracked flight
    /// counts here whether or not it's linked to a trip, and regardless of that trip's own
    /// `travelerIDs` (this used to be built from `trips` alone, which meant a standalone flight
    /// never counted at all, and a trip-linked one silently didn't count for whichever partner
    /// wasn't marked as a *trip* traveler even if they were correctly marked as a *flight*
    /// traveler — two independent fields that were never kept in sync). `trips` is passed
    /// separately purely as a lookup table: domestic/international/countries need a real country,
    /// which a raw `Flight`/`FlightAirport` (an AeroAPI or self-reported snapshot) never carries —
    /// only a linked trip's own curated `Place` does. A flight with no trip, or whose trip isn't
    /// in `trips`, simply doesn't contribute to those three specific breakdowns; every other stat
    /// below still counts it fully.
    init(flights: [Flight], trips: [Trip], couple: Couple) {
        flightCount = flights.count
        userFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerA.id) }
        partnerFlightCount = flights.count { $0.travelerIDs.contains(couple.partnerB.id) }

        // Each linked trip counted once (not once per leg) — matches how a trip's own stated
        // origin/destination represents the *overall* journey, same granularity `hero`'s
        // reunion-distance figure elsewhere in this file uses.
        let tripsByID = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
        let linkedTrips = Set(flights.compactMap(\.tripID)).compactMap { tripsByID[$0] }
        domesticCount = linkedTrips.count { $0.origin.country == $0.destination.country }
        internationalCount = linkedTrips.count { $0.origin.country != $0.destination.country }
        countries = Self.ranked(linkedTrips.flatMap { [$0.origin.country, $0.destination.country] })

        // Each flight's own great-circle distance, not a trip's `effectiveDistanceKm` — "long
        // haul" is naturally about a single flight, and a standalone long flight with no trip
        // attached obviously still qualifies.
        let flightDistances = flights.compactMap { flight -> Double? in
            guard let origin = flight.origin.coordinate, let destination = flight.destination.coordinate else { return nil }
            return Geo.distanceKm(origin, destination)
        }
        longHaulCount = flightDistances.count { $0 > Self.longHaulKm }
        totalDistanceKm = flightDistances.reduce(0, +)
        averageDistanceKm = flightDistances.isEmpty ? 0 : totalDistanceKm / Double(flightDistances.count)

        // From each flight's own scheduled/actual times — a trip's `departureDate`/`arrivalDate`
        // span the whole vacation (e.g. a 14-day trip), not how long any single flight was
        // actually in the air, which is what "Flight time" is supposed to mean.
        let durations = flights.compactMap { flight -> TimeInterval? in
            guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else { return nil }
            return arrival.timeIntervalSince(departure)
        }
        totalFlightTime = durations.reduce(0, +)
        averageFlightTime = durations.isEmpty ? 0 : totalFlightTime / Double(durations.count)
        longestFlightTime = durations.max() ?? 0

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
