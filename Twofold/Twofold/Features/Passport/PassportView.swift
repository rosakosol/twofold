//
//  PassportView.swift
//  Twofold
//
//  The "Stats" tab (still `MainTab.passport` internally, and the flight-specific card below
//  keeps the "Passport" name — only the tab itself was renamed, to reflect that relationship
//  stats, not just flight stats, are now the primary content). `RelationshipStatsCard` leads —
//  days together, trips, memories, and deeper milestones (reunions, longest/shortest trip,
//  longest separation, next reunion countdown). The passport card (flight-specific: routes,
//  airlines, airports) sits underneath as its own clearly-labeled secondary section. "All Flight
//  Stats" drills into the full flight breakdown (scoped All / user / partner via a segmented
//  control) — every card there individually shareable as an image. All computed from real trips,
//  never fabricated.
//

import SwiftUI

struct PassportView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingSnapshot = false

    private var flightStats: FlightStats {
        FlightStats(trips: appModel.trips, couple: appModel.couple)
    }

    private var relationshipStats: RelationshipMilestoneStats {
        RelationshipMilestoneStats(trips: appModel.trips, memories: appModel.memories, startedDatingOn: appModel.couple.startedDatingOn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("RELATIONSHIP STATS")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                            .padding(.leading, Theme.Spacing.xs)
                        RelationshipStatsCard(couple: appModel.couple, stats: relationshipStats)
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

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("PASSPORT")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                            .padding(.leading, Theme.Spacing.xs)
                        passportCard
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Stats")
            .sheet(isPresented: $showingSnapshot) {
                RelationshipStatsShareView(couple: appModel.couple, trips: appModel.trips, memories: appModel.memories, stats: relationshipStats)
            }
        }
    }

    // MARK: - Passport card

    /// Deliberately its own dark "cover" look, not `SectionCard` — every other card on this tab
    /// reads as an app screen; this one is styled to read as the actual travel document its
    /// name promises (navy cover, gold foil, engraved serif type, a bordered visa-page grid),
    /// while every number in it stays exactly as real as the rest of the app.
    private enum PassportInk {
        static let coverTop = Color(hex: "1B2A4A")
        static let coverBottom = Color(hex: "0B111F")
        static let gold = Color(hex: "D8B463")
        static let cream = Color(hex: "F3ECD9")
    }

    private var passportCard: some View {
        VStack(spacing: Theme.Spacing.lg) {
            passportHeader

            // Hero — same voice and type treatment as the All Flight Stats page, engraved
            // instead of the app's usual rounded/sky-blue treatment.
            VStack(spacing: Theme.Spacing.xs) {
                Text(appModel.couple.sharesHomeCity ? "Together, you've travelled" : "You've travelled")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(.white)

                Text("\(Text(MeasurementPreference.convertedValue(km: appModel.stats.totalDistanceKm), format: .number.precision(.fractionLength(0))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(PassportInk.gold))\(Text(" \(MeasurementPreference.unitSuffix())").font(.title.weight(.bold)).foregroundStyle(PassportInk.cream.opacity(0.85)))")

                if !appModel.couple.sharesHomeCity {
                    Text("for each other")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)

            coupleFlightPath

            passportDivider

            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                passportStat(label: "Flights", value: "\(flightStats.flightCount)")
                passportStat(label: "Flight time", value: FlightStats.duration(flightStats.totalFlightTime))
                passportStat(label: "Airports", value: "\(flightStats.airports.count)")
                passportStat(label: "Airlines", value: "\(flightStats.airlines.count)")
            }
            .frame(maxWidth: .infinity)

            NavigationLink {
                FullStatsView()
            } label: {
                HStack {
                    Text("All Flight Stats")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(PassportInk.gold)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 12)
                .background(PassportInk.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PassportInk.gold.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                LinearGradient(colors: [PassportInk.coverTop, PassportInk.coverBottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.06), .clear], center: .top, startRadius: 10, endRadius: 320)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            // Cover border, plus a slightly inset second line — the embossed double-rule
            // classic passport covers use around their emblem/title.
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(PassportInk.gold.opacity(0.55), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(PassportInk.gold.opacity(0.25), lineWidth: 1)
                .padding(7)
        }
    }

    /// The cover's title block — an emblem standing in for a national seal, "PASSPORT" in
    /// letter-spaced engraved serif.
    private var passportHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "seal.fill")
                .font(.system(size: 26))
                .foregroundStyle(PassportInk.gold)
            Text("PASSPORT")
                .font(.system(.title3, design: .serif).weight(.bold))
                .tracking(6)
                .foregroundStyle(PassportInk.cream)
        }
        .frame(maxWidth: .infinity)
    }

    private var passportDivider: some View {
        Rectangle()
            .fill(PassportInk.gold.opacity(0.3))
            .frame(height: 1)
    }

    /// Both partners joined by a dashed flight path with a plane at its midpoint.
    private var coupleFlightPath: some View {
        HStack(spacing: Theme.Spacing.sm) {
            AvatarView(person: appModel.currentUser, size: 56, showsRing: true)

            HorizontalDashedLine()
                .stroke(PassportInk.gold.opacity(0.6), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5]))
                .frame(height: 2)
                .overlay {
                    Image(systemName: "airplane")
                        .font(.subheadline)
                        .foregroundStyle(PassportInk.gold)
                        .padding(6)
                        .background(PassportInk.coverBottom, in: Circle())
                        .overlay { Circle().strokeBorder(PassportInk.gold.opacity(0.5), lineWidth: 1) }
                }

            AvatarView(person: appModel.partner, size: 56, showsRing: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func passportStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PassportInk.gold.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PassportInk.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Simple full-width horizontal line, drawn as a Shape so it can take a dashed stroke.
private struct HorizontalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
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
        case .user: appModel.trips.filter { $0.travelerID == appModel.currentUser.id }
        case .partner: appModel.trips.filter { $0.travelerID == appModel.partner.id }
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

            Text("\(Text(MeasurementPreference.convertedValue(km: scopedTrips.reduce(0) { $0 + $1.distanceKm }), format: .number.precision(.fractionLength(0))).font(.system(size: 44, weight: .bold, design: .rounded)).foregroundStyle(Theme.skyBlue))\(Text(" \(MeasurementPreference.unitSuffix())").font(.title.weight(.bold)).foregroundStyle(Theme.leafGreen))")

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
/// real trips. Flight-specific numbers only count trips that have a flight attached; the
/// countries list uses all trips (matching the long-standing `AppModel.stats.countryCount`).
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
        let flightTrips = trips.filter { $0.flight != nil }

        flightCount = flightTrips.count
        userFlightCount = flightTrips.count { $0.travelerID == couple.partnerA.id }
        partnerFlightCount = flightTrips.count { $0.travelerID == couple.partnerB.id }
        domesticCount = flightTrips.count { $0.origin.country == $0.destination.country }
        internationalCount = flightTrips.count { $0.origin.country != $0.destination.country }
        longHaulCount = flightTrips.count { $0.distanceKm > Self.longHaulKm }

        totalDistanceKm = flightTrips.reduce(0) { $0 + $1.distanceKm }
        averageDistanceKm = flightTrips.isEmpty ? 0 : totalDistanceKm / Double(flightTrips.count)

        let durations = flightTrips.map { max(0, $0.arrivalDate.timeIntervalSince($0.departureDate)) }
        totalFlightTime = durations.reduce(0, +)
        averageFlightTime = durations.isEmpty ? 0 : totalFlightTime / Double(durations.count)
        longestFlightTime = durations.max() ?? 0

        airports = Self.ranked(flightTrips.flatMap { [Self.airportName($0.origin), Self.airportName($0.destination)] })
        airlines = Self.ranked(flightTrips.compactMap { trip in
            let code = trip.flight?.flightNumber.prefix { $0.isLetter } ?? ""
            return code.isEmpty ? nil : code.uppercased()
        })
        routes = Self.ranked(flightTrips.map { trip in
            // Direction-agnostic, so MEL → LHR and LHR → MEL count as one route.
            [Self.airportName(trip.origin), Self.airportName(trip.destination)].sorted().joined(separator: " – ")
        })
        countries = Self.ranked(trips.flatMap { [$0.origin.country, $0.destination.country] })
    }

    private static func airportName(_ place: Place) -> String {
        place.iataCode?.uppercased() ?? place.city
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
