//
//  TripRowView.swift
//  Twofold
//

import SwiftUI

struct TripRowView: View {
    let trip: Trip
    let travelers: [Person]

    @Environment(AppModel.self) private var appModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The leading column carries the countdown number and the traveller avatars stacked under it.
    /// Both it and the number below were fixed values, so at larger text settings the count either
    /// stayed stubbornly at 17pt (it never scaled at all) or, once scaled, spilled out of a 38pt
    /// lane. Scaling the two together keeps the number inside its column at every size.
    @ScaledMetric(relativeTo: .subheadline) private var leadingColumnWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .subheadline) private var countdownFontSize: CGFloat = 17

    /// Date and duration read fine side by side ("12–18 Aug · 6 nights") until the row runs out of
    /// width, at which point `lineLimit(1)` clipped them rather than wrapping. Stacked at
    /// accessibility sizes, each gets the full width of the row.
    private var metaLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
    }

    /// Origin, arrow and destination share one line normally. At accessibility sizes three items
    /// across left each city about 32pt of width — "London" and "Melbourne" were being squeezed
    /// into a couple of characters and clipped. Stacked, each city gets the row's full width.
    private var routeLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
    }

    private var dateRangeText: String {
        let format = Date.FormatStyle().day().month(.abbreviated)
        if Calendar.current.isDate(trip.departureDate, inSameDayAs: trip.arrivalDate) {
            return trip.departureDate.formatted(format)
        }
        return "\(trip.departureDate.formatted(format)) – \(trip.arrivalDate.formatted(format))"
    }

    var body: some View {
        // Mirrors `TripCarouselCard`'s layout exactly (single leading column of countdown badge +
        // avatars, city-to-city full width on its own line, date range and duration combined on
        // one secondary line) — this row and that peek card used to diverge (this one split
        // duration/flight-number/status into a separate trailing column, with avatars on their
        // own row below), which made a trip look formatted differently depending on whether you
        // saw it in the peek carousel or the expanded list, for no real reason.
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                countdownBadge
                travelerAvatars
            }

            VStack(alignment: .leading, spacing: 2) {
                routeLayout {
                    Text(trip.origin.displayCity).lineLimit(1)
                    Image(systemName: "arrow.right")
                        // Points down once the route stacks, so it still reads as "from, to".
                        .rotationEffect(dynamicTypeSize.isAccessibilitySize ? .degrees(90) : .zero)
                        .accessibilityHidden(true)
                    Text(trip.destination.displayCity).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                // Shrink-to-fit is the right trade at normal sizes — one clean line beats a
                // wrapped city pair. At accessibility sizes it inverts: the point of the setting
                // is bigger text, and shrinking back down to honour a one-line cap defeats it.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

                metaLayout {
                    Text(dateRangeText)
                    // The middle dot only separates two things sitting on one line; stacked, it
                    // would read as a stray bullet.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("·")
                    }
                    Text(RelationshipMilestoneStats.tripDuration(trip))
                }
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .padding(Theme.Spacing.sm)
        // One coherent VoiceOver read ("5 days, Sydney to Tokyo, 12–18 Aug · 6 nights") instead of
        // the badge, avatars, cities, arrow icon, and date/duration line reading as five-plus
        // separate disconnected swipes.
        .accessibilityElement(children: .combine)
    }

    /// Centered under `countdownBadge` (same fixed-width column) rather than a separate row below
    /// the whole trip summary — same pairing `TripCarouselCard` uses.
    private var travelerAvatars: some View {
        HStack(spacing: -8) {
            ForEach(travelers) { person in
                AvatarView(person: person, size: 20)
                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
            }
        }
        .frame(width: leadingColumnWidth)
    }

    /// Replaces the old solo/paired avatar in this spot — days-to-go while the trip is still
    /// ahead, a "travelling now" state while it's actually underway (`trip.isActive`), and a
    /// simple done marker once it's over. A countdown wouldn't mean anything for the last two
    /// cases, so this isn't just "days-to-go, clamped to zero" for the whole row lifetime.
    @ViewBuilder
    private var countdownBadge: some View {
        VStack(spacing: 0) {
            if trip.departureDate > .now {
                let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0)
                Text(days == 0 ? "🎉" : "\(days)")
                    .font(.system(size: countdownFontSize, weight: .bold, design: .rounded))
                Text(days == 0 ? "Today" : (days == 1 ? "day" : "days"))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else if trip.isActive {
                Image(systemName: "airplane")
                    .font(.subheadline)
                    .foregroundStyle(Theme.skyBlue)
                    .accessibilityHidden(true)
                Text("Now")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.leafGreen)
                    .accessibilityHidden(true)
                Text("Done")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
        }
        .frame(width: leadingColumnWidth)
    }
}
