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
    /// Where "Add your anniversary" goes, for a couple who have not given one. Nil leaves the
    /// headline out instead — the share card, which has nowhere to go and should not carry a button
    /// into an image.
    var onAddAnniversary: (() -> Void)?
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
    @ScaledMetric(relativeTo: .title) private var timeTogetherFontSize: CGFloat = 34

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
        VStack(spacing: Theme.Spacing.md) {
            // The relationship's summary on `heroBlue` (section 6, Stats): the two of you, how
            // long, and the three numbers.
            StatsHeroCard(gradient: Theme.heroBlue, shareLabel: "Share relationship stats", onShare: onShare) {
                AvatarPair(me: couple.partnerA, partner: couple.partnerB, size: 44, isOnColour: true)

                if let timeTogether = stats.timeTogetherLabel {
                    Text(timeTogether)
                        .font(.system(size: timeTogetherFontSize, weight: .bold))
                        .tracking(-0.6)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                } else if let onAddAnniversary {
                    // No anniversary given: ask for it, rather than counting from today — which
                    // read "0 days" to a couple of any length.
                    Button(action: onAddAnniversary) {
                        Label("Add your anniversary", systemImage: "heart.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.raised, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.line, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }

                heroStatLayout {
                    if let daysTogether = stats.daysTogether {
                        StatsHeroNumber(label: "Days together", value: "\(daysTogether)", capsLines: capsLinesToFitGrid)
                    }
                    if showTripsStat {
                        StatsHeroNumber(label: "Trips", value: "\(stats.tripCount)", capsLines: capsLinesToFitGrid)
                    }
                    if showMemoriesStat {
                        StatsHeroNumber(label: "Memories", value: "\(stats.memoryCount)", capsLines: capsLinesToFitGrid)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Six tiles, coloured as the spec gives them: reunions coral, furthest apart blue,
            // longest trip green, shortest trip indigo, longest gap violet, next reunion coral.
            LazyVGrid(columns: milestoneColumns, spacing: Theme.Spacing.sm) {
                if showReunionsStat {
                    StatTile(icon: "heart.fill", label: "Total reunions", value: "\(stats.reunionCount)", chip: .coral)
                }
                StatTile(icon: "airplane", label: "Furthest apart", value: MeasurementPreference.distanceLabel(km: stats.longestDistanceKm), chip: .blue)
                StatTile(
                    icon: "arrow.up.right",
                    label: "Longest trip",
                    value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                    detail: stats.longestTrip?.destination.displayCity,
                    chip: .green
                )
                StatTile(
                    icon: "arrow.down.left",
                    label: "Shortest trip",
                    value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                    detail: stats.shortestTrip?.destination.displayCity,
                    chip: .indigo
                )
                StatTile(
                    icon: "hourglass",
                    label: "Longest gap",
                    value: stats.longestSeparationDays.map { "\($0) days" } ?? "—",
                    chip: .violet
                )
                StatTile(
                    icon: "calendar.badge.clock",
                    label: "Next reunion",
                    value: stats.nextReunionDaysToGo.map { $0 == 0 ? "Today" : "\($0) days" } ?? "Plan one",
                    detail: stats.nextReunion?.destination.displayCity,
                    chip: .coral
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
