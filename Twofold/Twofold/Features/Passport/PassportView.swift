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
                RelationshipStatsShareView(couple: appModel.couple, stats: relationshipStats)
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
                // Who on the left, when on the right — two independent filters that compose, so
                // they read as one control strip rather than two stacked rows eating vertical space
                // above the numbers they filter.
                HStack(spacing: Theme.Spacing.sm) {
                    Picker("Who", selection: $scope) {
                        Text("All").tag(StatScope.all)
                        Text(appModel.currentUser.name).tag(StatScope.user)
                        Text(appModel.partner.name).tag(StatScope.partner)
                    }
                    .pickerStyle(.segmented)

                    periodMenu
                }

                hero
                flightsSection
                distanceSection
                timeSection
                rankedSection(
                    icon: "building.2.fill",
                    title: "Top Visited Airports",
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
                    title: "Top Routes",
                    total: stats.routes.count,
                    unit: "routes",
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
        .sheet(item: $sharingStat) { stat in
            StatShareView(stat: stat)
        }
    }

    /// A menu rather than more segments: the year list grows without bound, and segments would
    /// squeeze the names beside them thinner every year the couple flies.
    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $period) {
                Text("All time").tag(StatPeriod.allTime)
                ForEach(availableYears, id: \.self) { year in
                    Text(String(year)).tag(StatPeriod.year(year))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(period.label)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 7)
            .themedCardBackground(cornerRadius: Theme.Radius.pill)
        }
        // Takes only the width it needs, leaving the rest of the row to the segmented control.
        .fixedSize()
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

            // Without this the headline number silently changes meaning when a year is picked —
            // the same big figure, now covering a slice, with nothing on screen saying which.
            if case .year(let year) = period {
                Text("in \(String(year))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
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
        shareableCard(icon: "clock.fill", title: "Flight Time", value: FlightStats.duration(stats.totalFlightTime), unit: nil) {
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
        shareableCard(icon: "airplane.circle.fill", title: "Top Airlines", value: "\(stats.airlines.count)", unit: "airlines") {
            if !stats.airlines.isEmpty {
                let isExpanded = expandedRankings.contains("Top Airlines")
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(stats.airlines.prefix(isExpanded ? stats.airlines.count : 3)) { entry in
                        airlineRow(entry)
                    }
                    if stats.airlines.count > 3 {
                        Button(isExpanded ? "Show less" : "Show all \(stats.airlines.count)") {
                            withAnimation {
                                if isExpanded { expandedRankings.remove("Top Airlines") } else { expandedRankings.insert("Top Airlines") }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.skyBlueText)
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

    private func rankedSection(icon: String, title: String, total: Int, unit: String, ranked: [FlightStats.Ranked]) -> some View {
        shareableCard(icon: icon, title: title, value: "\(total)", unit: unit) {
            if !ranked.isEmpty {
                rankedRows(title: title, ranked: ranked)
            }
        }
    }

    /// The card's first few entries, with a way to reach the rest.
    ///
    /// `collapsedLimit` is 3 here and 5 for countries, which is why the limit is a parameter rather
    /// than a constant — those lists were already different lengths and there's no reason to
    /// flatten them.
    private func rankedRows(title: String, ranked: [FlightStats.Ranked], collapsedLimit: Int = 3) -> some View {
        let isExpanded = expandedRankings.contains(title)
        return VStack(spacing: Theme.Spacing.sm) {
            ForEach(ranked.prefix(isExpanded ? ranked.count : collapsedLimit)) { entry in
                breakdownRow(label: entry.name, value: "×\(entry.count)")
            }
            if ranked.count > collapsedLimit {
                Button(isExpanded ? "Show less" : "Show all \(ranked.count)") {
                    withAnimation {
                        if isExpanded { expandedRankings.remove(title) } else { expandedRankings.insert(title) }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.skyBlueText)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Shows 5 before collapsing rather than the other cards' 3, plus a fixed 3x3 region grid
    /// underneath — countries are the one breakdown worth seeing more of at a glance.
    private var countriesSection: some View {
        shareableCard(icon: "globe.americas.fill", title: "Countries & Territories", value: "\(stats.countries.count)", unit: "countries") {
            if !stats.countries.isEmpty {
                rankedRows(title: "Countries & Territories", ranked: stats.countries, collapsedLimit: 5)

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
                statHeaderView(icon: icon, title: title, value: value, unit: unit)
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

/// The icon-circle + title row every `FlightStatsCard`-family card leads with, followed by the
/// big colored value/unit line — same visual role as `FlightStatsCard.heroStat`, just a single
/// value instead of three across. Free function (not a method on either view) so both
/// `FullStatsView`'s in-app card and `StatShareView`'s full-screen preview render an identical
/// header from the same source.
private func statHeaderView(icon: String, title: String, value: String, unit: String?) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(Theme.skyBlueText.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(Theme.skyBlueText)
            }
            .frame(width: 32, height: 32)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
        }
        Text("\(Text(value).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlueText))\(Text(unit.map { " \($0)" } ?? "").font(.title3.weight(.semibold)).foregroundStyle(Theme.subtleInk))")
    }
}

/// Everything `StatShareView` needs to re-render one `FullStatsView` section standalone — captured
/// once when its share button is tapped (see `FullStatsView.shareableCard`), since `rows` closures
/// only read already-available `stats`/`scope` state, not anything that changes while the sheet
/// is open.
private struct StatCardSpec: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let value: String
    let unit: String?
    let rows: AnyView
}

/// The full-screen "see it before you send it" preview for one Full Flight Stats card — same
/// flow `PassportShareView` already gives the summary Flight Stats card (card preview, Close,
/// and a `ShareLink` in the toolbar), just for a single section's card instead of the whole thing.
private struct StatShareView: View {
    let stat: StatCardSpec

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var appearance: ColorScheme?

    private var resolvedAppearance: ColorScheme { appearance ?? systemColorScheme }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    cardView
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.xl)
                        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
                }

                ShareCardAppearancePicker(selection: Binding(get: { resolvedAppearance }, set: { appearance = $0 }))
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(stat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview(stat.title, image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .postHogScreenView("Passport: Stat Share")
    }

    /// Same card format `PassportShareCard` uses for the summary Flight Stats card (brand mark up
    /// top, the card in `FlightStatsCard`'s own `SectionCard` chrome underneath, same corner
    /// radius/width) so this reads as a smaller sibling of that same share image.
    private var cardView: some View {
        VStack(spacing: Theme.Spacing.sm) {
            TwofoldBrandMark(color: Theme.ink, size: 24, textStyle: .title3)

            SectionCard {
                statHeaderView(icon: stat.icon, title: stat.title, value: stat.value, unit: stat.unit)
                stat.rows
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 360)
        .background(Theme.backgroundGradient)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .environment(\.colorScheme, resolvedAppearance)
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
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
    /// `allFlights` is filtered to the ones actually flown before anything is counted — see
    /// `Flight.hasBeenFlown`. A passport records where you've been, not where you're booked.
    init(flights allFlights: [Flight], couple: Couple) {
        let flights = allFlights.filter(\.hasBeenFlown)
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

        // Canonicalised across the whole set before counting, because the same airport or airline
        // can arrive under more than one identifier — see `airportCanonicaliser`.
        let airportKey = Self.airportCanonicaliser(flights.flatMap { [$0.origin, $0.destination] })
        let airlineKey = Self.airlineCanonicaliser(flights)

        airports = Self.ranked(flights.flatMap { [airportKey($0.origin), airportKey($0.destination)].compactMap { $0 } })
        airlines = Self.ranked(flights.compactMap(airlineKey))
        // Direction-agnostic, so MEL → SIN and SIN → MEL count as one route. A flight with an
        // unresolvable airport at either end contributes no route at all rather than a half-named
        // one — "MEL – —" would rank as its own distinct route, and every such flight would pile
        // into the same fake one.
        routes = Self.ranked(flights.compactMap { flight -> String? in
            guard let origin = airportKey(flight.origin), let destination = airportKey(flight.destination) else { return nil }
            return [origin, destination].sorted().joined(separator: " – ")
        })
    }

    /// One identity per airport, resolved across the whole set of flights rather than per flight.
    ///
    /// An airport is keyed by its IATA code, falling back to ICAO — and that fallback is what
    /// inflated the counts. A flight that resolved only an ICAO code contributed "YMML" while
    /// another through the same airport contributed "MEL", so Melbourne counted as two airports,
    /// two entries in Top Airports, and two separate routes to everywhere it connects. The
    /// reported symptom: three airports flown repeatedly showing as more than three.
    ///
    /// There's no airport table on the device to look codes up in, but the flights themselves
    /// carry the link: any airport that arrives with *both* codes tells us they're the same place.
    /// So one pass records those pairings, and a second resolves every airport through them. An
    /// ICAO code never seen alongside its IATA partner stays as it is — wrong to merge on a guess,
    /// and it's the honest answer for a set of flights that genuinely never identified them
    /// together.
    ///
    /// Not `displayCode`, which exists for *showing* an airport and falls back through `city` to a
    /// literal "—". Both fallbacks corrupt a count: a flight that resolved only a city contributed
    /// "Melbourne" as an airport distinct from another flight's "MEL", and every flight with
    /// nothing resolved contributed the same "—", which then ranked as a real airport someone had
    /// supposedly visited many times.
    private static func airportCanonicaliser(_ airports: [FlightAirport]) -> (FlightAirport) -> String? {
        var canonical: [String: String] = [:]
        for airport in airports {
            guard let iata = normalizedCode(airport.iata) else { continue }
            canonical[iata] = iata
            if let icao = normalizedCode(airport.icao) { canonical[icao] = iata }
        }
        return { airport in
            if let iata = normalizedCode(airport.iata) { return canonical[iata] ?? iata }
            if let icao = normalizedCode(airport.icao) { return canonical[icao] ?? icao }
            return nil
        }
    }

    /// The same idea for airlines, linked through the carrier's name instead of a second code.
    ///
    /// `airlineCode` is whatever the server resolved — `operator_iata` where it exists, ICAO
    /// otherwise — so one carrier can arrive as "SQ" on one flight and "SIA" on another and count
    /// twice. Flights that carry both a code and a name let the two be tied together; the shortest
    /// code wins as the canonical one, which is the IATA form the tailfin logos are keyed on.
    ///
    /// The prefix scrape survives only as a fallback for flights added before `airlineCode` was
    /// populated. It can't be trusted as a primary key: `flightNumber` is
    /// `marketingFlightNumber ?? flightNumberIATA`, so a codeshare reports the *marketing*
    /// carrier's prefix while a non-codeshare on the same airline reports its own — which is how
    /// five flights across three airlines once came out as four.
    private static func airlineCanonicaliser(_ flights: [Flight]) -> (Flight) -> String? {
        var byName: [String: String] = [:]
        for flight in flights {
            guard let code = rawAirlineKey(for: flight),
                  let name = flight.airlineName?.trimmingCharacters(in: .whitespaces).lowercased(),
                  !name.isEmpty else { continue }
            if let existing = byName[name], existing.count <= code.count { continue }
            byName[name] = code
        }
        return { flight in
            guard let code = rawAirlineKey(for: flight) else { return nil }
            guard let name = flight.airlineName?.trimmingCharacters(in: .whitespaces).lowercased() else { return code }
            return byName[name] ?? code
        }
    }

    private static func rawAirlineKey(for flight: Flight) -> String? {
        if let code = flight.airlineCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty {
            return code.uppercased()
        }
        let prefix = flight.flightNumber.prefix { $0.isLetter }
        return prefix.isEmpty ? nil : prefix.uppercased()
    }

    private static func normalizedCode(_ code: String?) -> String? {
        guard let trimmed = code?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
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
    PassportView(requestedSection: .constant(nil))
        .environment(AppModel())
}
