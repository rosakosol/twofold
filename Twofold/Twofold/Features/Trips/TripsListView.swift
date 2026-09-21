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

import PostHog
import SwiftUI

struct TripsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var tab: TripsTab = .trips
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    /// Tapping the solo-state empty hints below opens this rather than the add-trip/add-flight
    /// sheet — there's a real partner-required blocker before either of those would even work.
    @State private var showingPartnerGate = false
    @State private var detent: PanelDetent = .peek
    /// True for the exact duration of an active drag — set/cleared by `DraggablePanelHost`'s
    /// `UIPanGestureRecognizer`, entirely outside SwiftUI's own state-mutation/body-recompute
    /// pipeline (see that file's own header comment for why: every purely-SwiftUI-composed
    /// version of this drag glitched on slow/paused drags, regardless of how the gesture/state
    /// code was arranged). Still used the same way it always was — a guard against anything
    /// reacting to `settledDetent`/`detent` mid-gesture instead of only at rest.
    @State private var isDragging = false
    /// Which content the panel shows — only ever changed at rest, in `DraggablePanelHost`'s
    /// `onSettle` callback, alongside `detent` — never mid-drag, since the live-tracking phase
    /// no longer touches SwiftUI state at all.
    @State private var settledDetent: PanelDetent = .peek
    @State private var selectedTrip: Trip?
    @State private var selectedFlight: Flight?

    /// Long-press any row (in either tab) to enter this — every row grows a selection circle,
    /// tapping toggles membership instead of navigating, and the header swaps to a Cancel/Delete
    /// bar. Swipe-to-delete (single trip/flight, no mode change) only applies while this is
    /// false. Same convention as `MemoriesListView`'s multi-select, adapted to this panel's own
    /// header instead of a system toolbar, since this screen deliberately doesn't sit under one
    /// (see this file's own header comment).
    @State private var isSelecting = false
    @State private var selectedTripIDs: Set<Trip.ID> = []
    @State private var selectedFlightIDs: Set<Flight.ID> = []
    @State private var showingBulkDeleteConfirm = false
    @State private var hapticTrigger = false

    /// The drag handle's own frame. `dragHandle` pins itself to exactly this, so the panel's own
    /// arithmetic can rely on it rather than measuring it too.
    private let dragHandleHeight: CGFloat = 44

    /// Natural height of the header plus whatever `peekContent` is showing, measured rather than
    /// guessed.
    ///
    /// This was a literal — 583, and 416, 340 and 220 before that — re-calibrated by eye every
    /// time the header grew a row or the card grew a line. Every one of those values was wrong in
    /// a way no constant could fix: what peek has to fit depends on the couple. `peekItemLimit`
    /// cards, or one, or an empty-state hint are three different heights, and a number sized for
    /// the busiest of them left everyone else looking at a panel two thirds full of gradient with
    /// the globe hidden behind it.
    ///
    /// Measuring is right for all three, and for the Dynamic Type sizes no literal here was ever
    /// checked against. `nil` until the first layout pass reports back.
    @State private var measuredPeekBodyHeight: CGFloat?

    /// Height of the "Travel" title on its own — what minimised has to keep on screen.
    @State private var measuredTitleHeight: CGFloat?

    /// Stands in only until the first measurement lands, which is the very next layout pass. It
    /// is the last hand-calibrated value of `peekHeight`, so a measurement that never arrives
    /// degrades to the behaviour this replaced rather than to a collapsed panel.
    private let fallbackPeekHeight: CGFloat = 583

    private var peekHeight: CGFloat {
        guard let measuredPeekBodyHeight else { return fallbackPeekHeight }
        return dragHandleHeight + measuredPeekBodyHeight
    }

    /// The handle, the title, and the floating tab bar's clearance — nothing else.
    ///
    /// Dragging down is meant to get the panel out of the globe's way, and it still does. What it
    /// used to also do was take the title with it, leaving a slab of gradient with no title and no
    /// content, which reads as a rendering fault rather than as a collapsed panel. The title is
    /// what says the slab is the Travel panel, so it stays.
    ///
    /// The clearance is there for the same reason `peekBottomClearance` is: the tab bar sits
    /// outside this panel, so nothing here gets bottom-safe-area inset from it, and a panel
    /// shorter than the bar would sit behind it and be untouchable.
    private var minimisedHeight: CGFloat {
        dragHandleHeight + (measuredTitleHeight ?? 41) + Theme.Spacing.md + peekBottomClearance
    }

    /// Same idea (and same value) as `bottomListClearance` below, just for the peek-height card
    /// instead of the expanded list — the floating tab bar sits *outside* this panel entirely (see
    /// this file's own header comment), so nothing here gets automatic bottom-safe-area clearance
    /// from it. The old flat `Theme.Spacing.lg` wasn't real tab-bar clearance, just ordinary
    /// breathing room, so the card's own bottom edge ended up sitting behind/under the tab bar.
    private let peekBottomClearance: CGFloat = 100

    /// What the empty-state hint gets instead of `peekBottomClearance`.
    ///
    /// That constant is the tab bar plus ordinary breathing room, and the room is worth having
    /// under a card. Under a one-line hint it is not: the panel is only as tall as this hint makes
    /// it, so the slack is a visible fraction of the whole thing rather than a margin inside it.
    /// Measured against the tab bar itself — its buttons start 79pt above the panel's bottom edge,
    /// so this clears them with a little to spare and nothing more.
    private let emptyPeekBottomClearance: CGFloat = 88
    private let panelAnimation: Animation = .spring(response: 0.35, dampingFraction: 0.86)

    enum TripsTab: String, CaseIterable {
        case trips = "Trips"
        case flights = "Flights"
    }

    /// The one place `detent` and `settledDetent` move together outside a drag. They are separate
    /// so that content only swaps at rest (see `settledDetent`), which means every non-drag route
    /// to a new detent — the globe tap, the VoiceOver action — has to set both or the panel
    /// resizes while still showing the previous detent's content.
    private func settle(_ newDetent: PanelDetent) {
        guard newDetent != detent else { return }
        withAnimation(panelAnimation) {
            detent = newDetent
            settledDetent = newDetent
        }
    }

    private var detentDescription: String {
        switch detent {
        case .minimised: "Minimised"
        case .peek: "Collapsed"
        case .expanded: "Expanded"
        }
    }

    private func travelers(for trip: Trip) -> [Person] {
        let people = trip.travelerIDs.compactMap { appModel.couple.partner($0) }
        return people.isEmpty ? [appModel.currentUser] : people
    }

    private var selectedCount: Int {
        switch tab {
        case .trips: selectedTripIDs.count
        case .flights: selectedFlightIDs.count
        }
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
                let panelWidth = max(0, proxy.size.width - horizontalInset * 2)

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

                    // `.equatable()` skips re-running this view's `body` (which rebuilds `Map`'s
                    // whole content builder) on every parent re-render that doesn't actually
                    // change `trips`/`fallbackCenter` — see `TripsGlobeView`'s own `==` doc
                    // comment for why that matters while the panel below is being dragged.
                    TripsGlobeView(
                        trips: appModel.upcomingTrips,
                        fallbackCenter: appModel.currentUser.homeCity?.coordinate
                    )
                    .equatable()
                    // Tap the globe and the panel gets out of its way. One-directional on
                    // purpose: a tap on the map bringing the panel *back* would fire on every
                    // stray tap while you were trying to look at the thing you just uncovered.
                    // The handle drags it back up.
                    //
                    // `simultaneousGesture` rather than `onTapGesture`, because the map owns its
                    // own recognisers — an exclusive tap here would either be swallowed by them
                    // or, worse, win and stop the panning and zooming this screen is mostly for.
                    .simultaneousGesture(
                        TapGesture().onEnded { settle(.minimised) }
                    )

                    // Live height (during an active drag) and settled height (peek/expanded, at
                    // rest) are both owned by `DraggablePanelHost` itself now — see that file's
                    // own header comment for why the drag specifically has to escape SwiftUI's
                    // own diffing/layout pipeline, not just be reorganized within it.
                    DraggablePanelHost(
                        content: browsePanelContent(settledDetent: settledDetent, expandedHeight: expandedHeight)
                            .background(Theme.backgroundGradient),
                        // Both are measured now, so both are clamped here rather than trusted:
                        // the detents have to stay ordered (minimised <= peek <= expanded) or the
                        // drag has no room to resolve between them.
                        minimisedHeight: min(minimisedHeight, expandedHeight),
                        peekHeight: min(max(peekHeight, minimisedHeight), expandedHeight),
                        expandedHeight: expandedHeight,
                        cornerRadius: panelCornerRadius,
                        detent: $detent,
                        isDragging: $isDragging,
                        onSettle: { newDetent in
                            withAnimation(panelAnimation) {
                                detent = newDetent
                                settledDetent = newDetent
                            }
                        }
                    )
                    .frame(width: panelWidth, alignment: .top)
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
        .addContentSheet(isPresented: $showingAddTrip, canAdd: appModel.canAddContent, feature: .trips) {
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
            // `AddTripDetailsView` itself has no screen-view tag of its own — the onboarding
            // path only gets tagged because `OnboardingCoordinatorView`'s own choke point wraps
            // it externally. This is the *other* real caller (adding a trip post-onboarding, from
            // the Travel tab), and until now it fired with no screen event at all.
            .postHogScreenView("Travel: Add Trip")
        }
        .addContentSheet(isPresented: $showingAddFlight, canAdd: appModel.canAddContent, feature: .flights) {
            AddFlightView()
        }
        .sheet(isPresented: $showingPartnerGate) {
            PartnerRequiredGateView()
        }
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        // Switching tabs mid-selection would leave "N Selected" pointed at whichever set
        // matches the tab you're leaving, with no way to see or clear it from the tab you land
        // on — clearing both on every tab change keeps "what's selected" unambiguous.
        .onChange(of: tab) {
            isSelecting = false
            selectedTripIDs.removeAll()
            selectedFlightIDs.removeAll()
        }
        .alert(
            selectedCount == 1
                ? "Delete this \(tab == .trips ? "trip" : "flight")?"
                : "Delete \(selectedCount) \(tab == .trips ? "trips" : "flights")?",
            isPresented: $showingBulkDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Browse panel

    /// Everything the panel ever shows, as one plain SwiftUI view — no gesture attached here at
    /// all anymore. `DraggablePanelHost` hosts this and owns both the live drag-tracking and the
    /// settled peek/expanded height entirely in UIKit; this function only has to describe what
    /// the content looks like, the same as it always did.
    ///
    /// The `List` in `expandedContent` used to sit outside the gesture-attached view specifically
    /// so its own internal scroll gesture wouldn't fight a SwiftUI `DragGesture` layered on top of
    /// it. That's no longer a SwiftUI-vs-SwiftUI gesture conflict — `UIScrollView` (what `List` is
    /// backed by) and an ancestor `UIPanGestureRecognizer` coexisting correctly is a long-settled,
    /// heavily-used UIKit capability (this is exactly how e.g. Apple Maps' own bottom sheet nests
    /// a scrollable list inside a pannable card), not the ad-hoc arbitration two independent
    /// SwiftUI `DragGesture`s were stuck with.
    private func browsePanelContent(settledDetent: PanelDetent, expandedHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            dragHandle

            // The title is rendered at every detent, the controls and content only above
            // minimised. Minimised used to be the handle and nothing else, on the reasoning that a
            // panel meant to be out of the way should be entirely out of the way — but what that
            // actually produced was a slab of gradient with no title and nothing in it, which
            // reads as a screen that failed to draw rather than as a panel that collapsed.
            VStack(spacing: 0) {
                browseHeader(
                    showingControls: settledDetent != .minimised,
                    rhythm: headerRhythm(for: settledDetent)
                )

                if settledDetent == .peek {
                    peekContent
                        .transition(.opacity)
                }
            }
            // What `peekHeight` is built from. Measured here rather than inside `peekContent` so
            // that it covers the header too, and so that the flexible `Spacer` below — which has
            // no natural height of its own and would simply report back whatever height the panel
            // already had — stays outside it.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // Only at rest, and only while peek is what's actually laid out. Mid-drag the
                // panel is shorter than its content, so the stack is compressed and reports a
                // height that would feed straight back into the height driving the compression.
                guard !isDragging, settledDetent == .peek, height > 0 else { return }
                guard let previous = measuredPeekBodyHeight else {
                    // First measurement replaces `fallbackPeekHeight` in the same layout pass it
                    // was used, so animating it would animate a value nobody ever saw.
                    measuredPeekBodyHeight = height
                    return
                }
                // Sub-point differences are re-layout noise, not a changed card count.
                guard abs(height - previous) > 0.5 else { return }
                withAnimation(panelAnimation) { measuredPeekBodyHeight = height }
            }

            if settledDetent == .expanded {
                expandedContent
                    .transition(.opacity)
            } else {
                // What keeps the panel's bottom corners rounded — see `peekContent` for why that
                // is not obvious. It used to sit inside each of `peekContent`'s own branches;
                // hoisted out here so that the measurement above doesn't include it, and so that
                // minimised gets one too.
                Spacer(minLength: 0)
            }
        }
        // Explicit, so the peek-card/full-list swap always cross-fades rather than popping —
        // `settledDetent` now only ever changes once, at rest (`DraggablePanelHost`'s
        // `onSettle`), but this still keeps that one transition smooth.
        .animation(.easeInOut(duration: 0.2), value: settledDetent)
    }

    /// Purely a visual affordance now — the drag itself is recognized across the whole panel
    /// (`DraggablePanelHost`'s `UIPanGestureRecognizer`, attached to the panel as a whole), not
    /// just this capsule. Still carries the VoiceOver activation path, since a bare pan gesture
    /// doesn't reliably respond to VoiceOver's double-tap.
    private var dragHandle: some View {
        Capsule()
            .fill(Theme.subtleInk.opacity(0.35))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: dragHandleHeight)
            .contentShape(Rectangle())
            .accessibilityElement()
            .accessibilityLabel("Trip list")
            .accessibilityValue(detentDescription)
            .accessibilityAddTraits(.isButton)
            // Cycles rather than toggles, now that there are three of them — activating from
            // expanded wraps back to minimised, so every detent is reachable by VoiceOver without
            // a drag, which is the whole reason this action exists.
            .accessibilityAction {
                settle(detent == .expanded ? .minimised : detent.taller)
            }
    }

    /// `showingControls` is false at the minimised detent, where the picker, the add button and
    /// the selection bar all go and the title alone stays — see `minimisedHeight`. `rhythm` is the
    /// spacing between the header's own rows and the gap to whatever sits below it; see
    /// `headerRhythm(for:)`.
    private func browseHeader(showingControls: Bool, rhythm: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: rhythm) {
            // Multi-select is only enterable from a row, so it can't be entered while minimised —
            // but it can be left running *into* minimised, and a Cancel/Delete bar on a panel
            // showing neither the rows it acts on nor a way back to them is worse than the title.
            if isSelecting, showingControls {
                selectionHeader
            } else {
                // Matches Memories'/Games' own `.navigationTitle` weight — this panel is its own
                // screen in every way that matters, it just doesn't sit under a standard nav bar.
                // Collapsing is drag-only (the handle above) — no separate button, so there's
                // exactly one interaction to learn for both directions.
                Text("Travel")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    // Always on screen, so this never goes stale the way a measurement taken only
                    // at one detent would.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredTitleHeight = $0 }

                if showingControls {
                    HStack(spacing: Theme.Spacing.md) {
                        Picker("Section", selection: $tab) {
                            ForEach(TripsTab.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Goes straight to whichever add flow matches the currently-visible tab — this
                        // used to be a Menu offering both "Add Trip"/"Add Flight" regardless of `tab`,
                        // an extra tap that was redundant with the picker already showing what you're
                        // looking at. Only Flights still needs the partner gate — tracking depends on
                        // couple_id server-side (AeroAPI polling, push fan-out); Trips already has a
                        // solo-first local-then-sync path (`PendingTripStore`), same as onboarding's
                        // pre-pairing add-trip flow.
                        Button {
                            switch tab {
                            case .trips:
                                showingAddTrip = true
                            case .flights:
                                // Flights still needs a partner — tracking is wired through
                                // couple_id at the AeroAPI polling/push layer server-side, unlike
                                // Trips which already has a solo-first local-then-sync path.
                                guard appModel.partnerConnected else {
                                    showingPartnerGate = true
                                    return
                                }
                                showingAddFlight = true
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Theme.skyBlueText)
                        }
                    }
                }
            }
        }
        // `alignment: .leading` on the stack only places its children relative to each other — it
        // is the picker row that was making the stack full width. Without the picker the stack
        // shrank to the title and centred itself in the panel, so the title slid from the left
        // edge to the middle on the way down and back again on the way up.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        // Nothing sits below the title at minimised, so this would only be dead space above the
        // tab bar's clearance.
        .padding(.bottom, showingControls ? rhythm : 0)
    }

    /// Replaces the title/picker/add-button row while multi-selecting — this panel doesn't sit
    /// under a standard nav bar (see this file's own header comment), so the Cancel/Delete
    /// controls a system `.toolbar` would normally carry live here instead, right above the list
    /// they act on rather than at the very top of the screen, disconnected from it.
    private var selectionHeader: some View {
        HStack {
            Button("Cancel") {
                withAnimation(.snappy) {
                    isSelecting = false
                    selectedTripIDs.removeAll()
                    selectedFlightIDs.removeAll()
                }
            }
            .foregroundStyle(Theme.skyBlueText)

            Spacer(minLength: 0)

            Text("\(selectedCount) Selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 0)

            Button(role: .destructive) {
                showingBulkDeleteConfirm = true
            } label: {
                Text("Delete")
            }
            .disabled(selectedCount == 0)
        }
    }

    /// How many trips/flights the peek height shows before the rest need the expanded list.
    ///
    /// Was one, on the reasoning that a *scrollable* row of them read as "swipe to see your other
    /// trips" and so duplicated what expanding already does. That still holds — these are stacked,
    /// not scrollable, so peek stays a glance at what's next rather than a browsing mode of its
    /// own. It just shows two of them, which is what most couples have in flight at once anyway.
    private let peekItemLimit = 2

    /// True when peek is showing an empty-state hint rather than cards. Mirrors `peekContent`'s
    /// own two branches exactly — Trips on "any trip at all", Flights on *tracked* flights, since
    /// a couple with only completed ones still gets the hint.
    private var peekShowsEmptyHint: Bool {
        switch tab {
        case .trips: appModel.trips.isEmpty
        case .flights: appModel.activeOrUpcomingFlights.isEmpty
        }
    }

    /// The header's own row spacing, and the gap from it to whatever sits below.
    ///
    /// `lg` normally: title, then tabs, then content, matching the Stats tab's own title/tabs/card
    /// rhythm (`PassportView`'s `VStack(spacing: Theme.Spacing.lg)`). That replaced a much tighter
    /// `xs` here, which read noticeably cramped side by side with Stats.
    ///
    /// Tighter again when peek is showing an empty-state hint, because at that size the rhythm is
    /// most of what is holding the panel open. A card can carry a `lg` above it and still look
    /// deliberate; a title, a picker and one line of text separated by the same gaps just leave a
    /// panel mostly made of space, which is what this state looked like.
    private func headerRhythm(for detent: PanelDetent) -> CGFloat {
        detent == .peek && peekShowsEmptyHint ? Theme.Spacing.sm : Theme.Spacing.lg
    }

    @ViewBuilder
    private var peekContent: some View {
        switch tab {
        case .trips:
            if appModel.trips.isEmpty {
                // The cards below carry this; the hint needs it for the same reason — the
                // floating tab bar sits outside this panel, so nothing here is inset from it.
                emptyTripsHint
                    .padding(.bottom, emptyPeekBottomClearance)
            } else {
                let trips = Array(appModel.upcomingTrips.prefix(peekItemLimit))
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(trips) { trip in
                        Button {
                            selectedTrip = trip
                        } label: {
                            TripCarouselCard(trip: trip, travelers: travelers(for: trip))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // `.lg`, not `.md` — `TripCarouselCard`'s own shadow (radius 12) bleeds past its
                // edges, and `.md` alone wasn't enough clearance from the panel's own 40pt corner
                // radius: the shadow visibly muddied the rounded top corners, reading as "cut
                // off" rather than cleanly rounded. See `peekBottomClearance` for the matching
                // bottom-edge issue (the floating tab bar, not the corners).
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, peekBottomClearance)
            }
        case .flights:
            // Gated on *tracked* flights specifically, not "ever had any flight" — a couple
            // with only past/completed flights and nothing currently tracked should still see
            // the "add a flight" hint here, not an empty carousel with nothing to tap.
            if appModel.activeOrUpcomingFlights.isEmpty {
                // The cards below carry this; the hint needs it for the same reason — the
                // floating tab bar sits outside this panel, so nothing here is inset from it.
                emptyFlightsHint
                    .padding(.bottom, emptyPeekBottomClearance)
            } else {
                let flights = Array(appModel.activeOrUpcomingFlights.prefix(peekItemLimit))
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(flights) { flight in
                        Button {
                            selectedFlight = flight
                        } label: {
                            FlightCarouselCard(flight: flight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // See the matching `TripCarouselCard` stack's own comment above — same shadow-
                // into-corner-radius issue, same fix.
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, peekBottomClearance)
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
                    .listRowBackground(Color.clear)
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
        // `.insetGrouped`'s own built-in top inset used to stack with `browseHeader`'s own
        // `.padding(.bottom, lg)` right above it, leaving a much bigger gap between the tabs and
        // whatever's first in the list (typically the "Add a trip/flight" hint) than the same
        // header has above the peek carousel in the collapsed state. Zeroing this out makes
        // `browseHeader`'s own bottom padding the only gap either way, so expanded and collapsed
        // read with the same rhythm.
        .contentMargins(.top, 0, for: .scrollContent)
        // This whole screen deliberately ignores the safe area (see the header comment) so the
        // panel's rounded corners can sit behind the floating tab bar — which also means this
        // `List` never gets the automatic bottom clearance a normal screen's scroll content would
        // get from that tab bar. Without this, the last row of "Past flights"/"Past" (whichever
        // one happens to be the final section) renders right under the floating tab bar instead
        // of above it.
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: bottomListClearance) }
    }

    /// Clears the floating tab bar's own height plus a little breathing room below the last row —
    /// there's no shared constant for the system tab bar's height to reference, so this is a
    /// calibrated literal, same as `peekHeight`/`topBreathingRoom` above.
    private let bottomListClearance: CGFloat = 100

    @ViewBuilder
    private var tripSections: some View {
        let upcoming = appModel.upcomingTrips
        if !upcoming.isEmpty {
            Section("Upcoming") {
                ForEach(upcoming) { trip in
                    tripRow(trip)
                }
            }
        }

        let past = appModel.pastTrips
        if !past.isEmpty {
            Section("Past") {
                ForEach(past) { trip in
                    tripRow(trip)
                }
            }
        }
    }

    /// Swaps between a plain toggle-selection `Button` (selecting mode) and the regular
    /// tap-to-navigate + swipe-to-delete (normal mode) — same shape as `flightRow`/
    /// `MemoriesListView.row`. Long-pressing while *not* selecting enters selection mode with
    /// this trip pre-selected.
    @ViewBuilder
    private func tripRow(_ trip: Trip) -> some View {
        Group {
            if isSelecting {
                Button {
                    toggleTripSelection(trip)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        selectionIndicator(isSelected: selectedTripIDs.contains(trip.id))
                        TripRowView(trip: trip, travelers: travelers(for: trip))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    selectedTrip = trip
                } label: {
                    TripRowView(trip: trip, travelers: travelers(for: trip))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await appModel.deleteTrip(trip) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onLongPressGesture {
                    hapticTrigger.toggle()
                    withAnimation(.snappy) {
                        isSelecting = true
                        selectedTripIDs = [trip.id]
                    }
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
                .listRowBackground(Color.clear)
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

    /// Swaps between a plain toggle-selection `Button` (selecting mode) and the regular
    /// tap-to-navigate + swipe-to-delete (normal mode) — same shape as `tripRow`/
    /// `MemoriesListView.row`. Long-pressing while *not* selecting enters selection mode with
    /// this flight pre-selected.
    @ViewBuilder
    private func flightRow(_ flight: Flight) -> some View {
        Group {
            if isSelecting {
                Button {
                    toggleFlightSelection(flight)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        selectionIndicator(isSelected: selectedFlightIDs.contains(flight.id))
                        FlightRowView(flight: flight)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    selectedFlight = flight
                } label: {
                    FlightRowView(flight: flight)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await appModel.deleteFlight(flight) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onLongPressGesture {
                    hapticTrigger.toggle()
                    withAnimation(.snappy) {
                        isSelecting = true
                        selectedFlightIDs = [flight.id]
                    }
                }
            }
        }
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Theme.skyBlueText : Theme.subtleInk.opacity(0.35))
    }

    private func toggleTripSelection(_ trip: Trip) {
        hapticTrigger.toggle()
        if selectedTripIDs.contains(trip.id) {
            selectedTripIDs.remove(trip.id)
        } else {
            selectedTripIDs.insert(trip.id)
        }
    }

    private func toggleFlightSelection(_ flight: Flight) {
        hapticTrigger.toggle()
        if selectedFlightIDs.contains(flight.id) {
            selectedFlightIDs.remove(flight.id)
        } else {
            selectedFlightIDs.insert(flight.id)
        }
    }

    private func deleteSelection() {
        switch tab {
        case .trips:
            let toDelete = appModel.trips.filter { selectedTripIDs.contains($0.id) }
            Task {
                await appModel.deleteTrips(toDelete)
                isSelecting = false
                selectedTripIDs.removeAll()
            }
        case .flights:
            let toDelete = appModel.flights.filter { selectedFlightIDs.contains($0.id) }
            Task {
                await appModel.deleteFlights(toDelete)
                isSelecting = false
                selectedFlightIDs.removeAll()
            }
        }
    }

    @ViewBuilder
    private var emptyTripsHint: some View {
        // Unlike `emptyFlightsHint` below, Trips no longer needs a partner to add one — see the
        // toolbar `+` button's comment above.
        Button {
            showingAddTrip = true
        } label: {
            emptyHintCard(icon: "airplane.circle.fill", title: "Add your first trip", subtitle: "Tap to plan a reunion or a trip of your own.")
        }
        .buttonStyle(.plain)
        // Horizontal inset lives here (not at each call site) so both the peek carousel's and the
        // expanded list's zero-inset row (`.listRowInsets(EdgeInsets())`) get exactly one
        // application of it, rather than either doubling up or going edge-to-edge.
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var emptyFlightsHint: some View {
        if appModel.partnerConnected {
            Button {
                showingAddFlight = true
            } label: {
                // Not "Add your first flight" — this shows whenever there's nothing *currently*
                // tracked (see `flightSections`/`peekContent`'s own gating on
                // `activeOrUpcomingFlights`), which a couple with only past/completed flights
                // hits again after their last tracked flight lands. "First" would be actively
                // wrong for them.
                emptyHintCard(icon: "airplane.circle.fill", title: "Add a flight", subtitle: "Track a flight to see it here.")
            }
            .buttonStyle(.plain)
            // See `emptyTripsHint`'s identical padding for why this lives here rather than at
            // each call site.
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
        } else {
            Button {
                showingPartnerGate = true
            } label: {
                emptyHintCard(icon: "person.2.fill", title: "Partner required to add your first tracked flight", subtitle: "Track flights together once you're connected.")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private func emptyHintCard(icon: String, title: String, subtitle: String) -> some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    Circle().fill(Theme.skyBlue.opacity(0.15))
                    Image(systemName: icon).foregroundStyle(Theme.skyBlueText)
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
        // Without this, the card had nothing proposing a specific width to stretch the `Spacer`
        // above into, so it just hugged its own icon+text content instead of spanning the same
        // full row width a real trip/flight row does.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    TripsListView()
        .environment(AppModel())
}
