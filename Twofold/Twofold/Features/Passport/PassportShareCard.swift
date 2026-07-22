//
//  PassportShareCard.swift
//  Twofold
//
//  The shareable "passport" image — designed to actually read as a passport bio-data page
//  (cover band, bio row, engraved metadata fields, a machine-readable-zone-style footer) rather
//  than another rounded gradient stat card, using `PassportTheme`'s navy/gold/cream palette so
//  it's unmistakably this app's brand rather than a copy of any reference app's own colors. Every
//  figure on it comes straight from `FlightStats`/`WorldMap`, same as the in-app passport card.
//

import SwiftUI

struct PassportShareCard: View {
    let couple: Couple
    let person: Person
    let stats: FlightStats
    let visitedCountryNames: Set<String>

    private static let issueDateFormat = Date.FormatStyle().day(.twoDigits).month(.abbreviated).year(.twoDigits)

    private var placeOfIssue: String {
        person.homeCity?.iataCode ?? person.homeCity?.city ?? "—"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            coverBand
            passportDivider
            bioRow
            hero
            WorldVisitedMapView(visitedCountryNames: visitedCountryNames, unvisitedColor: .white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PassportTheme.gold.opacity(0.3), lineWidth: 1)
                }
            statGrid
            passportDivider
            metadataGrid
            mrzBlock
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 360)
        .background(
            ZStack {
                LinearGradient(colors: [PassportTheme.coverTop, PassportTheme.coverBottom], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.07), .clear], center: .top, startRadius: 10, endRadius: 380)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(PassportTheme.gold.opacity(0.55), lineWidth: 1.5)
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(PassportTheme.gold.opacity(0.25), lineWidth: 1)
                .padding(8)
        }
    }

    private var coverBand: some View {
        VStack(spacing: 6) {
            BiometricPassportSymbol(size: 30)
            Text("PASSPORT")
                .font(.system(.title2, design: .serif).weight(.bold))
                .tracking(7)
                .foregroundStyle(PassportTheme.cream)
            Text("PASSPORT • PASS • PASAPORTE")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(PassportTheme.gold.opacity(0.7))
            TwofoldBrandMark(color: PassportTheme.gold.opacity(0.85), size: 18, textStyle: .caption)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var bioRow: some View {
        HStack(spacing: Theme.Spacing.md) {
            AvatarView(person: person, size: 60, showsRing: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name.uppercased())
                    .font(.system(.headline, design: .serif).weight(.bold))
                    .foregroundStyle(PassportTheme.cream)
                Text("TWOFOLD PASSPORT HOLDER")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(PassportTheme.gold.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hero: some View {
        VStack(spacing: 2) {
            Text("\(stats.flightCount)")
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .foregroundStyle(PassportTheme.gold)
            Text("flights")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
    }

    private var statGrid: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            passportStat(label: "Distance", value: MeasurementPreference.distanceLabel(km: stats.totalDistanceKm))
            passportStat(label: "Flight time", value: FlightStats.duration(stats.totalFlightTime))
            passportStat(label: "Airports", value: "\(stats.airports.count)")
            passportStat(label: "Airlines", value: "\(stats.airlines.count)")
        }
        .frame(maxWidth: .infinity)
    }

    private var metadataGrid: some View {
        VStack(spacing: 6) {
            metadataRow(label: "Authority", value: "Twofold")
            metadataRow(label: "Place of issue", value: placeOfIssue)
            metadataRow(label: "Date of issue", value: Date.now.formatted(Self.issueDateFormat).uppercased())
            metadataRow(label: "Member since", value: couple.startedDatingOn.formatted(Self.issueDateFormat).uppercased())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(PassportTheme.cream.opacity(0.65))
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PassportTheme.cream)
        }
    }

    /// Purely decorative — styled after a machine-readable zone, not a functional/scannable one,
    /// built from the same real fields the metadata rows above show (name, member-since, issue
    /// date, place of issue).
    private var mrzBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.mrzLine1(name: person.name, memberSince: couple.startedDatingOn))
            Text(Self.mrzLine2(issueDate: .now, placeCode: placeOfIssue))
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(PassportTheme.cream.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
    }

    private var passportDivider: some View {
        Rectangle()
            .fill(PassportTheme.gold.opacity(0.3))
            .frame(height: 1)
    }

    private func passportStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PassportTheme.gold.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PassportTheme.cream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private static func mrzLine1(name: String, memberSince: Date) -> String {
        let cleanName = name.uppercased().replacingOccurrences(of: " ", with: "<")
        let dateCode = memberSince.formatted(issueDateFormat).replacingOccurrences(of: " ", with: "").uppercased()
        let core = "P<TWOFOLD<<\(cleanName)<<MEMBER\(dateCode)<<@TWOFOLD"
        return pad(core, to: 44)
    }

    private static func mrzLine2(issueDate: Date, placeCode: String) -> String {
        let dateCode = issueDate.formatted(issueDateFormat).replacingOccurrences(of: " ", with: "").uppercased()
        let core = "ISSUED\(dateCode)\(placeCode.uppercased())<<<<<<<<<<<<<<<<<<<<<<<<<<<<TWOFOLD.COM"
        return pad(core, to: 44)
    }

    private static func pad(_ string: String, to length: Int) -> String {
        string.count >= length ? String(string.prefix(length)) : string + String(repeating: "<", count: length - string.count)
    }
}

#Preview {
    PassportShareCard(
        couple: MockData.couple,
        person: MockData.dara,
        stats: FlightStats(trips: MockData.trips, couple: MockData.couple),
        visitedCountryNames: WorldMap.visitedNames(from: ["Australia", "Singapore", "United Kingdom"])
    )
    .padding()
    .background(Color.black)
}
