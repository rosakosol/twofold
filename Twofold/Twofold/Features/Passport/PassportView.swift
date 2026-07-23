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
    /// own travel" the way flight stats are personal, not a shared/couple figure.
    private var flightStats: FlightStats {
        FlightStats(trips: appModel.trips.filter { $0.travelerIDs.contains(appModel.currentUser.id) }, couple: appModel.couple)
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
                        TripStatsCard(stats: tripStats)
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

    private var scopedTrips: [Trip] {
        switch scope {
        case .all: appModel.trips
        case .user: appModel.trips.filter { $0.travelerIDs.contains(appModel.currentUser.id) }
        case .partner: appModel.trips.filter { $0.travelerIDs.contains(appModel.partner.id) }
        }
    }

    private var stats: FlightStats {
        FlightStats(trips: scopedTrips, couple: appModel.couple)
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

/// Everything the passport card, snapshot card, and full-stats page show, computed from
/// real trips — every field here, including `countries`, counts only trips that have a flight
/// actually attached, so "All Flight Stats" never mixes in a trip that was just planned/logged
/// with no real tracked flight behind it.
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

    init(trips: [Trip], couple: Couple) {
        let flightTrips = trips.filter { !$0.flights.isEmpty }

        // Per leg, not per trip — a trip with a connecting itinerary or a round trip (outbound +
        // return, each its own tracked `Flight`) is genuinely two-or-more flights, not one. Using
        // `flightTrips.count` here previously meant "Flights" quietly measured how many *trips*
        // had a flight attached rather than how many flights were actually flown, so a couple
        // with three round-trip vacations (six real flights) saw "Flights: 3" while every other
        // breakdown below (airports, airlines, routes) already counted all six legs — the two
        // numbers looked like they disagreed because one was counting trips and the other flights.
        flightCount = flightTrips.reduce(0) { $0 + $1.flights.count }
        userFlightCount = flightTrips.filter { $0.travelerIDs.contains(couple.partnerA.id) }.reduce(0) { $0 + $1.flights.count }
        partnerFlightCount = flightTrips.filter { $0.travelerIDs.contains(couple.partnerB.id) }.reduce(0) { $0 + $1.flights.count }
        domesticCount = flightTrips.count { $0.origin.country == $0.destination.country }
        internationalCount = flightTrips.count { $0.origin.country != $0.destination.country }
        // `effectiveDistanceKm` (not the raw trip `distanceKm`) so a connecting itinerary's real
        // flown distance counts — see Trip.effectiveDistanceKm.
        longHaulCount = flightTrips.count { $0.effectiveDistanceKm > Self.longHaulKm }

        totalDistanceKm = flightTrips.reduce(0) { $0 + $1.effectiveDistanceKm }
        averageDistanceKm = flightTrips.isEmpty ? 0 : totalDistanceKm / Double(flightTrips.count)

        // Per leg, from each flight's own scheduled/actual times — a trip's `departureDate`/
        // `arrivalDate` span the whole vacation (e.g. a 14-day trip), not how long any single
        // flight was actually in the air, which is what "Flight time" is supposed to mean. Using
        // the trip's own dates here was the bug behind a one-flight trip showing "336h" (=14
        // days) as its flight time instead of the real ~15-hour flight duration.
        let durations = flightTrips.flatMap { trip in
            trip.flights.compactMap { flight -> TimeInterval? in
                guard let departure = flight.bestDeparture, let arrival = flight.bestArrival, arrival > departure else { return nil }
                return arrival.timeIntervalSince(departure)
            }
        }
        totalFlightTime = durations.reduce(0, +)
        averageFlightTime = durations.isEmpty ? 0 : totalFlightTime / Double(durations.count)
        longestFlightTime = durations.max() ?? 0

        // Per-leg, not per-trip — a connecting itinerary (Melbourne → Singapore → London) really
        // did touch Singapore's airport and may well have flown two different airlines, neither
        // of which the trip's own stated origin/destination alone would surface.
        airports = Self.ranked(flightTrips.flatMap { trip in
            trip.flights.flatMap { [$0.origin.displayCode, $0.destination.displayCode] }
        })
        airlines = Self.ranked(flightTrips.flatMap { trip in
            trip.flights.compactMap { flight -> String? in
                let code = flight.flightNumber.prefix { $0.isLetter }
                return code.isEmpty ? nil : code.uppercased()
            }
        })
        routes = Self.ranked(flightTrips.flatMap { trip in
            // Direction-agnostic per leg, so MEL → SIN and SIN → MEL count as one route.
            trip.flights.map { [$0.origin.displayCode, $0.destination.displayCode].sorted().joined(separator: " – ") }
        })
        countries = Self.ranked(flightTrips.flatMap { [$0.origin.country, $0.destination.country] })
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
