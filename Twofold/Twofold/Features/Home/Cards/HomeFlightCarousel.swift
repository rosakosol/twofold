//
//  HomeFlightCarousel.swift
//  Twofold
//
//  Home's live and upcoming flights, one card per page.
//

import SwiftUI

/// Swipeable, one-card-per-page carousel when tracking more than one flight — `flights` is
/// already sorted soonest-departure-first by `AppModel.activeOrUpcomingFlights`. Falls back
/// to a single plain card (no paging chrome) when there's just one, since a carousel of one
/// page (and a single dot) reads oddly.
struct HomeFlightCarousel: View {
    let flights: [Flight]
    /// Which page is showing. Held by Home, so it survives the carousel giving way to the
    /// reunion card and coming back.
    @Binding var page: Flight.ID?

    var body: some View {
        Group {
            if flights.count == 1 {
                NavigationLink {
                    FlightTrackingView(flight: flights[0])
                } label: {
                    ActiveFlightCard(flight: flights[0])
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(flights) { flight in
                                NavigationLink {
                                    FlightTrackingView(flight: flight)
                                } label: {
                                    ActiveFlightCard(flight: flight)
                                }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal)
                                .id(flight.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                    .scrollPosition(id: $page)

                    HStack(spacing: 6) {
                        ForEach(flights) { flight in
                            Circle()
                                .fill(flight.id == (page ?? flights.first?.id) ? Theme.accent : Theme.textSecondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: page)
                }
            }
        }
    }
}

/// A live, AeroAPI-backed flight (or a self-reported one — either way, whatever
/// `Flight` actually has) — supersedes `nextReunionCard` whenever one exists, since it
/// carries real status/countdown instead of just a trip's planned dates.
struct ActiveFlightCard: View {
    let flight: Flight

    /// The 30pt route and its 20pt arrow, scaled with Dynamic Type from the sizes the design gives
    /// them (section 6, Home).
    @ScaledMetric(relativeTo: .title) private var routeSize: CGFloat = 30
    @ScaledMetric(relativeTo: .title3) private var arrowSize: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Side by side at ordinary sizes; stacked at accessibility sizes, where the two halves of a
    /// row no longer fit beside each other and each was being truncated to a few letters.
    private var rowLayout: AnyLayout { rowLayout(aligned: .center) }
    private var baselineRowLayout: AnyLayout { rowLayout(aligned: .firstTextBaseline) }

    private func rowLayout(aligned alignment: VerticalAlignment) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: alignment))
    }

    var body: some View {
        SectionCard {
            rowLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.status.isActivelyTracked ? "Tracking now" : "Next flight")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Theme.Spacing.xs) {
                        // 24pt, not 18 — at 18pt, .scaledToFill() cropping a wide tailfin logo
                        // into a near-square frame was cutting away most of the actual mark,
                        // reading as "no logo" even though it was technically rendering.
                        AirlineLogoView(url: flight.displayLogoURL, size: 24)
                        Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                StatusPill(flight: flight)
            }

            // The route as airport codes, 30pt bold (section 6, Home): "FCO → SFO". Codes are short
            // and fixed-width enough that the line never needs to shrink.
            baselineRowLayout {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(flight.origin.displayCode)
                    Image(systemName: "arrow.right")
                        .font(.system(size: arrowSize, weight: .bold))
                        .accessibilityLabel("to")
                    Text(flight.destination.displayCode)
                }
                .font(.system(size: routeSize, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }

                if let totalDurationSummary = flight.totalDurationSummary {
                    Text(totalDurationSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            rowLayout {
                Text(flight.countdownSummary)
                    .font(.body.bold())
                    .foregroundStyle(Theme.accent)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)

                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.sm) }

                // Port + local time for each end, stacked (not side by side) — a long-format
                // arrival time was pushing departure onto a second row when both fought for the
                // same line. Departure in the origin's timezone, arrival in the destination's,
                // same convention FlightTrackingView's journey rows use.
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
                    portTimeRow(icon: "airplane.departure", code: flight.origin.displayCode, time: flight.bestDeparture, timeZone: flight.origin.timeZone)
                    portTimeRow(icon: "airplane.arrival", code: flight.destination.displayCode, time: flight.bestArrival, timeZone: flight.destination.timeZone)
                }
            }

            // No separate linear progress bar here anymore — with the route drawn on the map
            // right below, a second progress indicator heading a different direction (straight
            // left-to-right vs. whichever way the actual route runs) read as confusing rather
            // than reinforcing. The map's own gradient line + plane/avatar marker already show
            // progress along the real path.
            //
            // Unconditional, not gated behind isActivelyTracked — FlightTrackingView already
            // shows this map for any flight regardless of status (FlightMapView has its own
            // graceful fallback for missing coordinates), so a merely-.scheduled flight on Home
            // was the one place showing no map at all, reading as a bug rather than by-design.
            // Shorter than the detail screen's map (200pt vs 260pt) — the same 40pt padding used
            // there left the route looking tiny and over-zoomed-out here, since the camera fit
            // reserves that margin on every edge regardless of how little vertical space is left
            // to fit the route in. A tighter margin lets the route fill more of the card, closer
            // to how it reads on the detail screen.
            FlightMapView(flight: flight, interactive: false, edgePadding: 12)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    /// A departure/arrival glyph + airport code + its local time — "—" when the time isn't
    /// known yet rather than omitting the row, so the pair always lines up evenly.
    private func portTimeRow(icon: String, code: String, time: Date?, timeZone: TimeZone?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(code).font(.caption.weight(.semibold)).lineLimit(1)
            Text(time.map { $0.formatted(Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute()) } ?? "—")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
