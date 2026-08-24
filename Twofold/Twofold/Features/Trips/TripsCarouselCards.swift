//
//  TripsCarouselCards.swift
//  Twofold
//
//  Compact cards for the Trips tab's peek-height browse sheet — floating directly over the
//  full-screen globe, unlike `TripRowView`/`FlightRowView` which are plain backgroundless rows
//  built for a `List`'s own chrome. Purpose-built rather than retrofitting those (which stay
//  exactly as they are for the sheet's expanded `.large`-detent list), so a little of their
//  countdown/summary logic is duplicated here in compact form rather than shared — small enough,
//  and each view's real job (single floating card vs. full-width list row) is different enough,
//  that forcing one shared implementation would cost more than the duplication does.
//

import SwiftUI

struct TripCarouselCard: View {
    let trip: Trip
    let travelers: [Person]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Same reasoning as `TripRowView`'s identical pair — this card and that row deliberately
    /// mirror each other, so the fixed 17pt count and 38pt lane were wrong in both the same way:
    /// the number ignored the reader's text setting entirely, and scaling it without widening the
    /// column would just push it out of frame.
    @ScaledMetric(relativeTo: .subheadline) private var leadingColumnWidth: CGFloat = 38
    @ScaledMetric(relativeTo: .subheadline) private var countdownFontSize: CGFloat = 17

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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

                // Back on one row now that this card spans the panel's full width (see
                // `TripsListView`'s single-card peek) rather than a narrow fixed-width carousel
                // card — there's room for both without crowding, so no reason to spend a whole
                // extra line on the duration alone.
                metaLayout {
                    Text(dateRangeText)
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
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// Centered under `countdownBadge` (same fixed 38pt column) rather than floating at the
    /// card's own bottom-left — the badge is what these travelers are "for", so pairing them
    /// visually reads more directly than a separate row.
    private var travelerAvatars: some View {
        HStack(spacing: -8) {
            ForEach(travelers) { person in
                AvatarView(person: person, size: 20)
                    .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 1.5))
            }
        }
        .frame(width: leadingColumnWidth)
    }

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

struct FlightCarouselCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                AirlineLogoView(url: flight.displayLogoURL, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(flight.origin.displayCode)
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                        Text(flight.destination.displayCode)
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(flight.countdownSummary)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack {
                Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                Spacer()
                // See FlightRowView's matching check — a pending (not-yet-trackable) flight's
                // `status` still just reads "Scheduled", indistinguishable from a normal live one.
                if flight.faFlightID == nil {
                    PillBadge(text: "Not live yet", tint: Theme.subtleInk)
                } else {
                    PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        Color.blue.ignoresSafeArea()
        VStack {
            TripCarouselCard(trip: MockData.reunionTrip, travelers: [MockData.rosa, MockData.dara])
            FlightCarouselCard(flight: MockData.activeFlight)
        }
    }
}
