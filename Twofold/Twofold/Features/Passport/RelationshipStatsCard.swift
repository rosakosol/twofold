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

    var body: some View {
        SectionCard {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Theme.Spacing.md) {
                    coupleHeader

                    Text(stats.timeTogetherLabel)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
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

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.sm), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                        if showReunionsStat {
                            milestoneTile(icon: "heart.fill", label: "Total Reunions", value: "\(stats.reunionCount)", tint: Theme.heartRed)
                        }
                        milestoneTile(icon: "airplane", label: "Longest Distance", value: MeasurementPreference.distanceLabel(km: stats.longestDistanceKm), tint: Theme.skyBlue)
                        milestoneTile(
                            icon: "arrow.up.right",
                            label: "Longest Trip",
                            value: stats.longestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.longestTrip?.destination.displayCity,
                            tint: Theme.leafGreen
                        )
                        milestoneTile(
                            icon: "arrow.down.left",
                            label: "Shortest Trip",
                            value: stats.shortestTrip.map { RelationshipMilestoneStats.tripDuration($0) } ?? "—",
                            detail: stats.shortestTrip?.destination.displayCity,
                            tint: Theme.leafGreen
                        )
                        milestoneTile(
                            icon: "hourglass",
                            label: "Longest Separation",
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
                .fill(Theme.heartRed.opacity(0.4))
                .frame(width: 56, height: 2)
                .overlay {
                    Image(systemName: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.heartRed)
                        .padding(6)
                        .background(Theme.cardBackground, in: Circle())
                }

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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private func milestoneTile(icon: String, label: String, value: String, detail: String? = nil, tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon).font(.subheadline).foregroundStyle(tint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
