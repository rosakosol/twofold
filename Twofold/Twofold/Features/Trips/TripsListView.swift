//
//  TripsListView.swift
//  Twofold
//
//  Full-screen interactive globe (`TripsGlobeView`) with an always-present browse panel docked to
//  the bottom — drawn as regular inline content (not a system `.sheet`), so it can float above the
//  MainTabView's own tab bar without ever covering it. A system sheet presented from inside a tab
//  disables that tab bar underneath for as long as it's up, which is fine for a momentary
//  drill-in (trip/flight detail, added below as real sheets) but not for a panel that's meant to
//  be on screen permanently — that would leave the tab bar permanently untappable. At the peek
//  height the panel shows a horizontal card carousel (upcoming trips or tracked flights, depending
//  on the Trips/Flights picker); dragged (or tapped) to expanded it swaps to the full Upcoming/
//  Past (or Tracked/Past) list, which is how Past trips/flights stay reachable. Tapping any card
//  or row opens that trip's or flight's own details as a real sheet — a *momentary* modal is
//  exactly the case system sheets are fine for.
//

import SwiftUI

struct TripsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tab: TripsTab = .trips
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    /// Tapping the solo-state empty hints below opens this rather than the add-trip/add-flight
    /// sheet — there's a real partner-required blocker before either of those would even work.
    @State private var showingPartnerGate = false
    @State private var isExpanded = false
    /// Live finger position while dragging the handle, folded into the panel's rendered height so
    /// it tracks the gesture 1:1. Plain `@State`, not `@GestureState` — `@GestureState` resets to
    /// 0 the instant the gesture ends, *before* `.onEnded`'s own state mutation lands, which
    /// visibly snapped the panel back to its pre-drag height for a frame before animating to the
    /// real target (the "glitchy" jump). Driving this from `@State` and clearing it in the same
    /// explicit `withAnimation` block as the `isExpanded` flip below makes both changes land in
    /// one animated step instead of two.
    @State private var dragOffset: CGFloat = 0
    @State private var selectedTrip: Trip?
    @State private var selectedFlight: Flight?

    // Bumped up from 220 now that the header itself carries an extra row (the "Travel" title) and
    // the carousel card itself grew a line (duration split onto its own line from the date range)
    // — the old value was sized for a shorter header/card and was leaving the card cut off at the
    // bottom of the panel's fixed height instead of comfortably visible.
    private let peekHeight: CGFloat = 340
    private let panelAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.86)

    enum TripsTab: String, CaseIterable {
        case trips = "Trips"
        case flights = "Flights"
    }

    private func travelers(for trip: Trip) -> [Person] {
        let people = trip.travelerIDs.compactMap { appModel.couple.partner($0) }
        return people.isEmpty ? [appModel.currentUser] : people
    }

    /// Inset from each side — narrower than full width so the panel reads as its own floating
    /// card rather than a full-bleed sheet, just a little wider than `MainTabView`'s own floating
    /// tab bar rather than matching it exactly.
    private let horizontalInset: CGFloat = 12
    /// Matches the corner curvature of `MainTabView`'s own floating (iOS 18+ "Tab" API) tab bar —
    /// noticeably rounder than `Theme.Radius.card` (20, used by regular content cards), which read
    /// visibly less round side by side with the tab bar this panel sits directly above. Local to
    /// this view rather than a `Theme.Radius` change, since ordinary cards elsewhere aren't meant
    /// to match tab-bar curvature.
    private let panelCornerRadius: CGFloat = 40

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                // Ignoring *all* edges on this GeometryReader (below) makes `proxy.size` the true
                // full screen size — including the tab bar's reserved space at the bottom — while
                // `proxy.safeAreaInsets.top` still reports how tall the status bar/Dynamic Island
                // region is, so it can be kept clear manually instead of relying on the view
                // "respecting" a safe area it no longer participates in. Computing against the
                // true full height and deliberately extending past the tab bar (rather than
                // computing against the tab-bar-excluded height and trying to get a partial
                // `ignoresSafeArea(edges: .bottom)` to claw the difference back on just the panel)
                // is what actually gets the panel's rounded corners behind the tab bar reliably —
                // the partial-edge approach looked right in some layouts but not others.
                // `topBreathingRoom` keeps a real sliver of globe visible/reachable above the
                // panel even fully expanded, rather than the panel reaching literally the top of
                // the screen.
                let topBreathingRoom: CGFloat = 64
                let expandedHeight = proxy.size.height - proxy.safeAreaInsets.top - topBreathingRoom
                let restingHeight = isExpanded ? expandedHeight : peekHeight
                let panelHeight = min(expandedHeight, max(peekHeight, restingHeight - dragOffset))
                let panelWidth = max(0, proxy.size.width - horizontalInset * 2)
                // Which content the panel shows tracks the *live* dragged height, not just the
                // settled `isExpanded` state — previously the panel's height grew smoothly in
                // real time as you dragged (following `panelHeight` above) while still showing
                // the single peek card the whole way, only swapping to the full list at the very
                // end once `isExpanded` flipped in the drag's `.onEnded`. That mismatch (a smooth
                // height animation the entire gesture, then a hard content pop right as your
                // finger lifts) is what read as glitchy. Crossing this partway through the drag
                // instead means the list is already showing well before release, so the swap
                // blends into the motion rather than landing as a jarring finishing move.
                let showingExpandedContent = panelHeight > peekHeight + 60

                ZStack(alignment: .bottom) {
                    // `TripsGlobeView` shrinks its own rendered content below its layout frame
                    // (see its `.scaleEffect` doc comment) to look more zoomed out than MapKit's
                    // clamped camera distance alone allows — this sits behind it so the now-
                    // exposed margin reads as more of the same black space, not a jarring white
                    // edge showing through to whatever's otherwise behind it in this ZStack.
                    // `ignoresSafeArea()` applied once to the whole `ZStack` below (not to each
                    // layer individually) — applying it per-child left the odd case, on some
                    // layouts, of this `Color.black` not actually reaching full screen width.
                    Color.black

                    TripsGlobeView(
                        trips: appModel.upcomingTrips,
                        fallbackCenter: appModel.currentUser.homeCity?.coordinate
                    )

                browsePanel(showingExpandedContent: showingExpandedContent)
                    .frame(width: panelWidth, height: panelHeight, alignment: .top)
                    .background(Theme.backgroundGradient)
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
                    .padding(.bottom, 12)
                }
                .ignoresSafeArea()
            }
            .ignoresSafeArea()
            // Pushed onto this same `NavigationStack` (not presented as a sheet) — tapping a trip
            // or flight card now moves to an in-line screen the same way the rest of the app's
            // "tap a row, see its detail" flows do, rather than opening a second modal on top of
            // the globe+panel.
            .navigationDestination(item: $selectedTrip) { trip in
                TripDetailsView(trip: trip)
            }
            .navigationDestination(item: $selectedFlight) { flight in
                FlightTrackingView(flight: flight)
            }
        }
        .sheet(isPresented: $showingAddTrip) {
            NavigationStack {
                AddTripDetailsView(mode: .standalone, partnerName: appModel.partner.name) { _ in
                    showingAddTrip = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { showingAddTrip = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddFlight) {
            AddFlightView()
        }
        .sheet(isPresented: $showingPartnerGate) {
            PartnerRequiredGateView()
        }
    }

    // MARK: - Browse panel

    private func browsePanel(showingExpandedContent: Bool) -> some View {
        VStack(spacing: 0) {
            dragHandle
            browseHeader

            if showingExpandedContent {
                expandedContent
                    .transition(.opacity)
            } else {
                peekContent
                    .transition(.opacity)
            }
        }
        // Explicit, so the peek-card/full-list swap always cross-fades — including when
        // `showingExpandedContent` flips mid-drag from a slow, continuous `.onChanged` update
        // (those aren't wrapped in `withAnimation` themselves, only the drag's `.onEnded` settle
        // is), which is exactly when the swap used to pop with no transition at all. A fast
        // swipe never showed this: it crosses the threshold as part of `.onEnded`'s own animated
        // settle, so the pop just happened to ride along with that animation instead of standing
        // out on its own.
        .animation(.easeInOut(duration: 0.2), value: showingExpandedContent)
    }

    /// The only part of the panel a drag gesture attaches to — restricting it to this small,
    /// generously-hit-tested handle (rather than the whole panel) avoids fighting the expanded
    /// state's own `List` for scroll-vs-resize gestures.
    private var dragHandle: some View {
        Capsule()
            .fill(Theme.subtleInk.opacity(0.35))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            // Fixed 44pt hit region — this used to be just the capsule's own 5pt height plus
            // `Theme.Spacing.sm` (8pt) padding on each side, a 21pt-tall target well under
            // Apple's 44pt minimum recommended touch target, which is exactly why the drag so
            // often failed to register at all. The capsule glyph itself stays visually small;
            // only the tappable/draggable area grows.
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                // One gesture handles both tap-to-toggle and drag-to-resize, rather than a
                // separate `.onTapGesture` alongside this `DragGesture` — two simultaneous
                // gesture recognizers on the same view have to disambiguate a quick tap from
                // the start of a drag, which was its own source of dropped/ignored taps.
                // `minimumDistance: 0` makes the drag start tracking immediately on touch-down
                // (rather than waiting for ~10pt of movement before `onChanged` fires at all),
                // which is what made the whole gesture feel unresponsive/laggy to begin with.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let draggedUp = value.translation.height < -40 || value.predictedEndTranslation.height < -80
                        let draggedDown = value.translation.height > 40 || value.predictedEndTranslation.height > 80
                        // Both changes land inside the same explicit animation so the panel
                        // animates directly from wherever the drag left it to the final target
                        // height in one motion — letting `dragOffset` reset via an implicit/
                        // `@GestureState`-driven reset outside this block is what caused the old
                        // "snap back, then animate" glitch.
                        withAnimation(panelAnimation) {
                            if draggedUp {
                                isExpanded = true
                            } else if draggedDown {
                                isExpanded = false
                            } else if abs(value.translation.height) < 10 {
                                // Barely moved at all — a tap, not a drag that fell short of the
                                // expand/collapse threshold.
                                isExpanded.toggle()
                            }
                            dragOffset = 0
                        }
                    }
            )
    }

    private var browseHeader: some View {
        // `lg` between title and tabs, and again between the header and whatever's below (see
        // this view's own `.padding(.bottom, lg)`) — matches the Stats tab's own title/tabs/card
        // rhythm (`PassportView`'s `VStack(spacing: Theme.Spacing.lg)`), rather than the tighter
        // `xs` this used before, which read noticeably more cramped side by side with Stats.
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Matches Memories'/Games' own `.navigationTitle` weight — this panel is its own
            // screen in every way that matters, it just doesn't sit under a standard nav bar.
            // Collapsing is drag-only (the handle above) — no separate button, so there's exactly
            // one interaction to learn for both directions.
            Text("Travel")
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: Theme.Spacing.md) {
                Picker("Section", selection: $tab) {
                    ForEach(TripsTab.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Button {
                        showingAddTrip = true
                    } label: {
                        Label("Add Trip", systemImage: "airplane")
                    }
                    Button {
                        showingAddFlight = true
                    } label: {
                        Label("Add Flight", image: "boarding-pass")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.skyBlue)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.lg)
    }

    /// Exactly one card — the single soonest upcoming trip/flight, not a scrollable row of them —
    /// with the rest reachable only by expanding to the full list below. A horizontal carousel
    /// here (even a non-paging, freely-scrolling one) still read as "swipe to see your other
    /// trips", which duplicated what expanding already does and made peek feel like its own
    /// separate browsing mode instead of a quick glance at what's next.
    @ViewBuilder
    private var peekContent: some View {
        switch tab {
        case .trips:
            if appModel.trips.isEmpty {
                emptyTripsHint.padding(.horizontal, Theme.Spacing.md)
                Spacer(minLength: 0)
            } else if let trip = appModel.upcomingTrips.first {
                Button {
                    selectedTrip = trip
                } label: {
                    TripCarouselCard(trip: trip, travelers: travelers(for: trip))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        case .flights:
            // Gated on *tracked* flights specifically, not "ever had any flight" — a couple
            // with only past/completed flights and nothing currently tracked should still see
            // the "add a flight" hint here, not an empty carousel with nothing to tap.
            if appModel.activeOrUpcomingFlights.isEmpty {
                emptyFlightsHint.padding(.horizontal, Theme.Spacing.md)
                Spacer(minLength: 0)
            } else if let flight = appModel.activeOrUpcomingFlights.first {
                Button {
                    selectedFlight = flight
                } label: {
                    FlightCarouselCard(flight: flight)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        List {
            if tab == .trips, appModel.trips.isEmpty {
                emptyTripsHint
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            switch tab {
            case .trips:
                tripSections
            case .flights:
                flightSections
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var tripSections: some View {
        let upcoming = appModel.upcomingTrips
        if !upcoming.isEmpty {
            Section("Upcoming") {
                ForEach(upcoming) { trip in
                    Button {
                        selectedTrip = trip
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        let past = appModel.pastTrips
        if !past.isEmpty {
            Section("Past") {
                ForEach(past) { trip in
                    Button {
                        selectedTrip = trip
                    } label: {
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Tracked flights (soonest departure first, see `AppModel.activeOrUpcomingFlights`) above
    /// completed ones — every flight ever added lives in this one tab now, trip-linked or not,
    /// rather than splitting untethered ones off into a separate Past Flights screen.
    @ViewBuilder
    private var flightSections: some View {
        let tracked = appModel.activeOrUpcomingFlights
        if !tracked.isEmpty {
            Section("Tracked flights") {
                ForEach(tracked) { flight in
                    flightRow(flight)
                }
            }
        } else {
            // Nothing currently tracked — show the "add a flight" hint here even if there's
            // real history below in Past flights, rather than only when the tab has never had
            // any flight at all.
            emptyFlightsHint
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
        }

        let completed = appModel.completedFlights
        if !completed.isEmpty {
            Section("Past flights") {
                ForEach(completed) { flight in
                    flightRow(flight)
                }
            }
        }
    }

    private func flightRow(_ flight: Flight) -> some View {
        Button {
            selectedFlight = flight
        } label: {
            FlightRowView(flight: flight)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await appModel.deleteFlight(flight) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var emptyTripsHint: some View {
        if appModel.partnerConnected {
            Button {
                showingAddTrip = true
            } label: {
                emptyHintCard(icon: "airplane.circle.fill", title: "Add your first trip", subtitle: "Tap to plan a reunion or a trip of your own.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        } else {
            Button {
                showingPartnerGate = true
            } label: {
                emptyHintCard(icon: "person.2.fill", title: "Invite your partner to add your first trip together", subtitle: "Trips are better planned together.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    @ViewBuilder
    private var emptyFlightsHint: some View {
        if appModel.partnerConnected {
            Button {
                showingAddFlight = true
            } label: {
                emptyHintCard(icon: "airplane.circle.fill", title: "Add your first flight", subtitle: "Track a flight to see it here.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        } else {
            Button {
                showingPartnerGate = true
            } label: {
                emptyHintCard(icon: "person.2.fill", title: "Invite your partner to share your first tracked flight", subtitle: "Track flights together once you're connected.")
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private func emptyHintCard(icon: String, title: String, subtitle: String) -> some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: icon).foregroundStyle(Theme.skyBlue)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    TripsListView()
        .environment(AppModel())
}
