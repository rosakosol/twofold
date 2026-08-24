//
//  RelationshipStatsCard.swift
//  Twofold
//
//  The primary card on the (renamed) Stats tab — everything about the relationship itself,
//  not just flights: days together, trips, memories, plus a grid of deeper milestones. The
//  flight-specific numbers stay in their own "Passport" card below this one.
//

import SwiftUI

struct RelationshipStatsCard: View {
    let couple: Couple
    let stats: RelationshipMilestoneStats
    /// Inline share affordance in the card's own corner — replaces the old standalone "Create a
    /// snapshot" button that used to sit below this card on the Stats tab. Nil hides the button
    /// entirely (e.g. for the share card's own preview, which has nothing to open).
    var onShare: (() -> Void)?
    /// The Stats-tab in-app card always shows everything (these default to `true`) — only the
    /// share card's "Stats to include" customization ever turns one of these off, matching the
    /// exact three numbers `RelationshipStatsShareCard`'s photo-story layout already lets you
    /// toggle (trip/reunion/memory counts), so both layouts respect the same picks.
    var showTripsStat = true
    var showReunionsStat = true
    var showMemoriesStat = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The two headline sizes were fixed points, so they were the only text on the Stats tab that
    /// ignored the reader's text setting outright — the numbers this card exists to show stayed
    /// small while every label around them grew.
    @ScaledMetric(relativeTo: .title) private var timeTogetherFontSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var heroValueFontSize: CGFloat = 22

    /// Two columns of milestone tiles at normal sizes. At accessibility sizes each tile gets barely
    /// half the card's width, and since every line inside is capped to one line with a shrink
    /// factor, the result was text that got *smaller* the larger the reader's setting — the exact
    /// inverse of the intent. One column gives each tile the full width instead.
    private var milestoneColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())]
    }

    /// Three hero stats across is the same story one level up — stacked, each keeps its full width.
    private var heroStatLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.sm))
    }

    /// Equal tile heights are what the one-line caps buy, and they only matter while tiles sit
    /// side by side. In a single column there is no neighbour to match, so the caps come off and
    /// the text is free to wrap and grow.
    private var capsLinesToFitGrid: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        SectionCard {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    coupleHeader

                    Text(stats.timeTogetherLabel)
                        .font(.system(size: timeTogetherFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    heroStatLayout {
                        heroStat(label: "Days Together", value: "\(stats.daysTogether)")
                        if showTripsStat {
                            heroStat(label: "Trips", value: "\(stats.tripCount)")
                        }
                        if showMemoriesStat {
                            heroStat(label: "Memories", value: "\(stats.memoryCount)")
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    LazyVGrid(columns: milestoneColumns, spacing: Theme.Spacing.sm) {
                        if showReunionsStat {
                            milestoneTile(icon: "heart.fill", label: "Total Reunions", value: "\(stats.reunionCount)", tint: Theme.heartRedText)
                        }
                        milestoneTile(icon: "airplane", label: "Furthest Apart", value: MeasurementPreference.distanceLabel(km: stats.longestDistanceKm), tint: Theme.skyBlueText)
                        milestoneTile(
                            icon: "arrow.up.right",
                            label: "Longest Trip",
                            value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.longestTrip?.destination.displayCity,
                            tint: Theme.leafGreenText
                        )
                        milestoneTile(
                            icon: "arrow.down.left",
                            label: "Shortest Trip",
                            value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.shortestTrip?.destination.displayCity,
                            tint: Theme.leafGreenText
                        )
                        milestoneTile(
                            icon: "hourglass",
                            label: "Longest Gap",
                            value: stats.longestSeparationDays.map { "\($0) days" } ?? "—",
                            tint: .purple
                        )
                        milestoneTile(
                            icon: "calendar.badge.clock",
                            label: "Next Reunion",
                            value: stats.nextReunionDaysToGo.map { $0 == 0 ? "Today!" : "\($0) days" } ?? "Plan one",
                            detail: stats.nextReunion?.destination.displayCity,
                            tint: .orange
                        )
                    }
                }

                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                            .padding(8)
                            .background(Theme.backgroundGradient, in: Circle())
                    }
                    .accessibilityLabel("Share relationship stats")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Both avatars joined by a line with a heart at its center — the same "two people, one
    /// connection" visual language as `PassportView`'s flight path, but a plain heart-red line
    /// rather than a dashed route with a plane, since this card is about the relationship
    /// itself, not a specific journey between two airports. Fixed-width (not flexible/stretched
    /// edge to edge) and the whole group centered via the `Spacer()`s on either side — a
    /// full-width line reached all the way to the card's top-trailing corner, where it visually
    /// collided with the inline share button there.
    private var coupleHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Spacer(minLength: 0)

            AvatarView(person: couple.partnerA, size: 44, showsRing: true)

            Rectangle()
                .fill(Theme.heartRedText.opacity(0.4))
                .frame(width: 56, height: 2)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.heartRedText)
                        .padding(6)
                        .background(Theme.cardBackground, in: Circle())
                }
                .accessibilityHidden(true)

            AvatarView(person: couple.partnerB, size: 44, showsRing: true)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(capsLinesToFitGrid ? 1 : nil)
                .minimumScaleFactor(capsLinesToFitGrid ? 0.8 : 1)
            Text(value)
                .font(.system(size: heroValueFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(capsLinesToFitGrid ? 1 : nil)
                .minimumScaleFactor(capsLinesToFitGrid ? 0.6 : 1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func milestoneTile(icon: String, label: String, value: String, detail: String? = nil, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                // `.lineLimit(1)` here matters as much as the value/detail reservation below —
                // without it, a longer label ("Furthest Apart", "Longest Separation")
                // wraps to 2 lines while its shorter row-neighbor ("Total Reunions", "Next
                // Reunion") stays on 1, so the two tiles in that row end up different heights
                // despite the value/detail lines already being reserved consistently.
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(capsLinesToFitGrid ? 1 : nil)
                    .minimumScaleFactor(capsLinesToFitGrid ? 0.75 : 1)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(capsLinesToFitGrid ? 1 : nil)
                    .minimumScaleFactor(capsLinesToFitGrid ? 0.8 : 1)
                // Always reserve the detail line's height (even when there's no detail) so every
                // tile in the grid ends up the same height — some milestones (reunions, longest
                // separation) never have a detail string, which otherwise made their tiles shorter
                // than their row neighbors.
                Text(detail ?? " ")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(capsLinesToFitGrid ? 1 : nil)
                    .opacity(detail == nil ? 0 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .themedCardBackground(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RelationshipStatsCard(
        couple: MockData.couple,
        stats: RelationshipMilestoneStats(couple: MockData.couple, trips: MockData.trips, memories: MockData.memories)
    )
    .padding()
    .background(Theme.backgroundGradient)
}
