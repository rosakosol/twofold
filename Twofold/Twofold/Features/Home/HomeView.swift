//
//  GlobeHomeView.swift
//  Twofold
//

import SwiftUI

/// `.sheet(item:)` needs `Identifiable` — a plain tuple can't back it, so the distance card's
/// share button hands off through this instead.
private struct DistanceShareContext: Identifiable {
    let id = UUID()
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double
}

/// Same reason as `DistanceShareContext` — `.fullScreenCover(item:)` needs `Identifiable`, and the
/// globe needs both cities and the distance, none of which are in scope where the cover is
/// attached. Carrying them from the tap also means the screen that opens shows the figures the
/// card showed, rather than re-deriving them a moment later from somewhere else.
private struct GlobeFullScreenContext: Identifiable {
    let id = UUID()
    let myCity: Place
    let partnerCity: Place
    let distanceKm: Double
}

struct HomeView: View {
    /// Set by `MainTabView` to flip its own tab selection to Games, passed straight through to
    /// `RecommendedGamesSection`'s "See all games" — defaults to a no-op so the preview below
    /// still compiles.
    var onSeeAllGames: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSnapshot = false
    @State private var distanceShareContext: DistanceShareContext?
    @State private var globeFullScreenContext: GlobeFullScreenContext?
    @State private var showingSettings = false
    @State private var showingPartnerSetup = false
    @State private var reviewingConnectionRequest: BackendService.PendingConnectionRequest?
    @State private var showingPendingOutgoingDetail = false
    @State private var showingAddTrip = false
    @State private var showingPaywall = false
    @State private var showingAddFlight = false
    @State private var showingLocationPermission = false
    @State private var pendingShares: [PendingFlightShare] = []
    @State private var reviewingShare: PendingFlightShare?
    @State private var weatherReading: CurrentWeatherReading?
    @State private var weatherFetchedForCityID: UUID?
    @State private var myWeatherReading: CurrentWeatherReading?
    @State private var myWeatherFetchedForCityID: UUID?
    @State private var flightCarouselPage: Flight.ID?
    @State private var partnerDisconnectedAlert: String?

    private var distanceKm: Double? {
        guard let mine = appModel.currentUser.homeCity?.coordinate, let theirs = appModel.partner.homeCity?.coordinate else { return nil }
        return Geo.distanceKm(mine, theirs)
    }

    /// City + country name match — not a distance/coordinate threshold (a coordinate-only check
    /// would misfire for two different, merely nearby suburbs; see `WidgetSnapshotWriter`'s
    /// identical check for the same reasoning). Case/whitespace-insensitive: since home cities
    /// can come from live device location now (not just the manual city picker — see
    /// `live_location` in the codebase history), the same real city can reverse-geocode to
    /// strings that only differ in case or incidental whitespace between the two partners'
    /// devices, which a strict `==` treated as two different cities — showing the redundant
    /// two-line "It's X for them / It's X for you" `TimeZoneCard` (with two weather readings)
    /// for a couple who are, in fact, in the exact same city with a real but small distance
    /// between their two device-reported coordinates.
    private var sameCity: Bool {
        guard let mine = appModel.currentUser.homeCity, let theirs = appModel.partner.homeCity else { return false }
        return mine.city.caseInsensitiveCompare(theirs.city) == .orderedSame
            && mine.country.caseInsensitiveCompare(theirs.country) == .orderedSame
    }

    private var soonestTrip: Trip? {
        appModel.upcomingTrips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Neither card is dismissable, so the subscription state is what takes them
                    // away: resubscribing clears both without anything having to be acknowledged.
                    // Nested rather than two sibling conditions so the lapsed card cannot outlive
                    // the situation it describes.
                    // Waits to be told, rather than assuming the worst while it finds out.
                    // `canAddContent` is false before the first answer lands as well as when
                    // somebody genuinely has not paid, and rendering the second on the way to the
                    // first flashed "No active subscription" at a paying subscriber on every
                    // launch. Same shape as `invitePartnerCard` below, and for the same reason: no
                    // card is better than the wrong one, and the gap is one round trip.
                    if appModel.hasResolvedSubscription, !appModel.canAddContent {
                        if let lapsedPartnerName = appModel.partnerSubscriptionLapsedPartnerName {
                            // The specific reason, when there is one. Shown instead of the general
                            // card rather than as well as it — two cards saying "you have no
                            // subscription" one above the other is noise, and this one says more.
                            subscriptionLapsedCard(partnerName: lapsedPartnerName)
                        } else {
                            noSubscriptionCard
                        }
                    }

                    if let incomingRequest = appModel.pendingConnectionRequests.first {
                        pendingConnectionRequestCard(incomingRequest)
                    } else if let outgoingRequest = appModel.pendingOutgoingConnectionRequest {
                        pendingOutgoingInviteCard(outgoingRequest)
                    } else if appModel.needsPartnerInvite && appModel.hasResolvedOutgoingConnectionRequest {
                        // Waits to be told there is no pending request before offering to send one.
                        //
                        // `pendingOutgoingConnectionRequest` is nil both when there is no request and
                        // when the lookup has not landed, and this branch read the second as the
                        // first — so an invitee arriving at Home met "Set up your partner", the one
                        // thing they had already done, until the fetch caught up a moment later.
                        // Nothing takes its place in the gap: no card is better than the wrong one,
                        // and the gap is one round trip.
                        invitePartnerCard
                    }
                    setupChecklistCard
                    pendingSharesCard
                    if let partnerTimeZone = appModel.partner.homeCity?.timeZone {
                        TimeZoneCard(
                            person: appModel.partner,
                            timeZone: partnerTimeZone,
                            comparisonTimeZone: appModel.currentUser.homeCity?.timeZone,
                            sameCity: sameCity,
                            cityName: appModel.partner.homeCity?.displayCity,
                            weather: weatherReading,
                            myWeather: myWeatherReading
                        )
                    }
                    if !appModel.activeOrUpcomingFlights.isEmpty {
                        flightCarousel(flights: appModel.activeOrUpcomingFlights)
                    } else if let soonestTrip {
                        nextReunionCard(trip: soonestTrip)
                    }
                    if let myCity = appModel.currentUser.homeCity, let partnerCity = appModel.partner.homeCity {
                        if sameCity {
                            sameCityCard(city: myCity)
                        } else if let distanceKm {
                            distanceCard(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity)
                        }
                    } else if appModel.hasLoadedCoupleState, appModel.needsOwnHomeCity {
                        homeCityPromptCard
                    } else if appModel.hasLoadedCoupleState, appModel.needsPartnerHomeCity {
                        partnerHomeCityPendingCard
                    }
                    // Nothing in the remaining case — a solo user who has set their own city. There
                    // is no distance to show and nobody to wait on, and `invitePartnerCard` above
                    // already owns the "connect with someone" prompt.
                    if appModel.partnerConnected {
                        DrawingPadCard()
                    }
                    RecommendedGamesSection(onSeeAllGames: onSeeAllGames)
                }
                .padding(Theme.Spacing.md)
            }
            .background(ScreenBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        // A gear, not a person. This opens Settings, and the toolbar already
                        // carries both faces in its centre — a second person glyph beside them
                        // read as a profile, which is not where it goes.
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) {
                    // DESIGN: 34pt rather than the spec's 44pt. A 44pt photo with its ring is taller
                    // than the navigation bar's content area and gets clipped there.
                    AvatarPair(
                        me: appModel.currentUser,
                        partner: appModel.partnerConnected ? appModel.partner : nil,
                        size: 34
                    )
                }
            }
            .sheet(item: $reviewingShare, onDismiss: refreshPendingShares) { share in
                PendingFlightShareReviewView(share: share)
            }
            .refreshable { await pullToRefresh() }
            .onAppear {
                refreshPendingShares()
                Task { await appModel.refreshCoupleStateIfNeeded() }
                Task { await appModel.refreshTrips() }
                Task { await appModel.refreshFlights() }
                Task { await appModel.refreshMemories() }
                Task { await refreshWeatherIfNeeded() }
                if appModel.needsPartnerInvite {
                    Task { await appModel.refreshPendingConnectionRequests() }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshPendingShares()
                    // Not `refreshCoupleStateIfNeeded()` here too — `RootView`'s own
                    // `onChange(of: scenePhase)` already calls it at the app root on every
                    // foreground, and since `HomeView` only ever mounts once that's already
                    // resolved `MainTabView`, both fired concurrently on *every single*
                    // foreground. Piled on top of `checkSubscription()` (also fired from
                    // `RootView` on the same event) and this view's own `refreshFlights()`/
                    // `refreshWeatherIfNeeded()` below, that meant several concurrent calls all
                    // hitting Supabase's auth/session layer at once on every foreground — the
                    // real cause behind an occasional main-thread hang/watchdog kill traced back
                    // to `AuthClient.session` lock contention in a live crash report.
                    Task { await appModel.refreshFlights() }
                    Task { await refreshWeatherIfNeeded() }
                    if appModel.needsPartnerInvite {
                        Task { await appModel.refreshPendingConnectionRequests() }
                    }
                }
            }
            .sheet(isPresented: $showingSnapshot) { SnapshotShareView() }
            .sheet(item: $distanceShareContext) { context in
                DistanceShareView(couple: appModel.couple, myCity: context.myCity, partnerCity: context.partnerCity, distanceKm: context.distanceKm)
            }
            // A cover rather than a sheet: a sheet keeps Home's cards visible behind a rounded
            // card of its own, and this is a globe you turn — the grabber and the inset edges
            // would both be things to catch a drag meant for the earth.
            .fullScreenCover(item: $globeFullScreenContext) { context in
                RelationshipGlobeFullScreenView(
                    couple: appModel.couple,
                    myCity: context.myCity,
                    partnerCity: context.partnerCity,
                    activeTrip: appModel.activeTrip,
                    distanceKm: context.distanceKm
                )
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingLocationPermission) { NavigationStack { LocationPermissionView() } }
            .addContentSheet(isPresented: $showingAddFlight, canAdd: appModel.canAddContent, feature: .flights) { AddFlightView() }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack { PaywallView() }
            }
            .sheet(isPresented: $showingPartnerSetup) {
                PartnerSetupView()
            }
            .sheet(item: $reviewingConnectionRequest) { request in
                ConnectionRequestReviewView(request: request)
            }
            .sheet(isPresented: $showingPendingOutgoingDetail) {
                if let request = appModel.pendingOutgoingConnectionRequest {
                    PendingConnectionApprovalView(request: request)
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
            }
            .onChange(of: appModel.partnerDisconnectedMessage) { _, newValue in
                guard let newValue else { return }
                partnerDisconnectedAlert = newValue
                appModel.partnerDisconnectedMessage = nil
            }
            // Reconnecting retires the notice. The message is copied into local state above and
            // the model's copy cleared immediately, so clearing the model on re-adopt cannot
            // dismiss an alert that has already been taken — leaving "your connection with X has
            // ended" sitting over a Home screen that was showing the new couple.
            .onChange(of: appModel.partnerConnected) { _, isConnected in
                if isConnected { partnerDisconnectedAlert = nil }
            }
            .alert("Your connection has ended", isPresented: Binding(
                get: { partnerDisconnectedAlert != nil },
                set: { if !$0 { partnerDisconnectedAlert = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(partnerDisconnectedAlert ?? "")
            }
        }
    }

    /// Why access changed, for somebody who did not choose it.
    ///
    /// `leave_couple` records this on the non-payer's profile when the partner who was covering the
    /// subscription disconnects. It used to be a full-screen takeover shown in place of the forced
    /// paywall — which was the right instinct in the wrong shape: the takeover appeared once, and
    /// its "Not now" cleared the flag permanently, so anyone who tapped it and came back a week
    /// later found a paywall and no explanation. With the wall gone there is nothing to take over
    /// anyway.
    ///
    /// A card instead, sitting above the partner cards because it explains something that has just
    /// happened where those are about what to do next. It stays until dismissed, and dismissing it
    /// costs nothing now: the app is still there underneath.
    private func subscriptionLapsedCard(partnerName: String) -> some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Your subscription has ended", systemImage: "person.badge.minus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("\(partnerName) was covering your Twofold subscription, and your connection with them has ended. Nothing has been deleted — your trips, memories and photos are in Settings → Help → Archived data, and you can export them from there.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Named rather than left to be discovered. An archive is deleted ninety days after
                // the connection ends, and somebody who has just been told their subscription
                // stopped is exactly the person who will not go looking for that date.
                Text("An archive is kept for 90 days and then permanently deleted. The date is shown on it.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // One action, and no dismiss. This is the state of the account rather than an
                // announcement that has been made and is over, so it goes when the state does —
                // see the `canAddContent` check that now wraps both of these cards. Same shape as
                // `noSubscriptionCard`, which it stands in for.
                Button("See plans") { showingPaywall = true }
                    .buttonStyle(.twofoldPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What is true of the app right now, for somebody without a subscription.
    ///
    /// The prompts on each gated action explain themselves when tapped, but only to somebody who
    /// tapped — this is for the person opening the app and wondering why it feels different.
    /// Deliberately not dismissable: it is not an announcement that has been made and is over, it
    /// is the state of the account, and it disappears on its own when that changes.
    private var noSubscriptionCard: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("No active subscription", systemImage: "lock.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("Everything you've already saved is still here, and always will be — you can read it, export it and delete it at any time. What needs a subscription is adding to it: new trips, memories, flights and today's question.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("See plans") { showingPaywall = true }
                    .buttonStyle(.twofoldPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var setupChecklistCard: some View {
        // Trip/flight rows need a connected partner to make sense — the dedicated
        // `invitePartnerCard` above already owns that prompt, so this checklist only ever shows
        // those two rows once a partner exists. "Turn on location access" is independent of
        // partner status and still shows regardless.
        // `hasLoadedCoupleState` first: `needsFirstTrip` is `trips.isEmpty` and `needsFirstFlight`
        // reads the same empty array, so before the fetch this card confidently told everyone to add
        // their first trip and flight — including couples with fifty of each.
        if appModel.hasLoadedCoupleState, !appModel.setupChecklistDismissed, !checklistItems.isEmpty {
            SectionCard {
                // One child, not two. `SectionCard` spaces its children by `md` (16), which is
                // right between a card's distinct parts — but the header here is not a distinct
                // part, it is the list's own title, and the 44pt dismiss button already inflates
                // that row well past the text it contains. The two together left this card with a
                // gap no other card has, wide enough to read as a missing row.
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Finish setting up Twofold")
                            .font(.headline)
                        Spacer()
                        Button {
                            appModel.dismissSetupChecklist()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary.opacity(0.5))
                                // The glyph alone is ~22pt, half Apple's 44pt minimum — a miss on this
                                // one dismisses nothing and taps the card behind it instead. The frame
                                // only grows the tap target; `contentShape` makes the whole of it
                                // hittable rather than just the glyph's own pixels, and the icon keeps
                                // its original size.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Cancels the padding the 44pt box adds on the trailing side, so the icon still
                        // sits where it did against the card's edge.
                        .padding(.trailing, -Theme.Spacing.xs)
                        .accessibilityLabel("Dismiss")
                    }

                    // Rows flush against each other, separated by a rule rather than by space —
                    // each already carries a 44pt tap target, so a gap on top of that put three
                    // items in a card tall enough to look padded by mistake, with spaces wide
                    // enough to read as tappable while hitting nothing. The rule does the
                    // separating that the space was failing to do, the same way `nextReunionCard`
                    // divides its two halves.
                    VStack(spacing: 0) {
                        ForEach(Array(checklistItems.enumerated()), id: \.element.id) { index, item in
                            // Between rows only. A divider written next to each row would leave a
                            // stray rule above the first or below the last, and which row is first
                            // changes as they get completed.
                            if index > 0 {
                                Divider()
                            }
                            checklistRow(task: item.task, action: item.action)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingSharesCard: some View {
        if let first = pendingShares.first {
            SectionCard {
                Button {
                    reviewingShare = first
                } label: {
                    HStack {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.15))
                            Image(systemName: "envelope.badge").foregroundStyle(Theme.accent)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pendingShares.count == 1 ? "1 flight email to review" : "\(pendingShares.count) flight emails to review")
                                .font(.headline)
                            Text("Shared from Mail — tap to add the flight")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func refreshPendingShares() {
        pendingShares = PendingShareStore.all()
    }

    /// Only re-fetches when the relevant city actually changes — WeatherKit calls aren't free,
    /// and the time card only needs a fresh reading roughly hourly, not on every foreground. A
    /// failed fetch does NOT mark the city as fetched, so a transient/auth error gets retried on
    /// the next foreground instead of leaving the card permanently blank. Fetches the partner's
    /// and the user's own city in parallel — the card shows both now, one per time line.
    /// `force` is what a pull-to-refresh passes: the same-city guard below is there to keep the
    /// *automatic* refreshes cheap, and honouring it when someone has deliberately pulled the
    /// screen down would make the gesture a no-op on the one card most likely to look stale.
    private func refreshWeatherIfNeeded(force: Bool = false) async {
        async let partner: Void = refreshPartnerWeatherIfNeeded(force: force)
        async let mine: Void = refreshMyWeatherIfNeeded(force: force)
        _ = await (partner, mine)
    }

    private func refreshPartnerWeatherIfNeeded(force: Bool = false) async {
        guard let city = appModel.partner.homeCity else { return }
        guard force || weatherFetchedForCityID != city.id else { return }
        if let reading = await TwofoldWeatherService.currentWeather(for: city) {
            weatherReading = reading
            weatherFetchedForCityID = city.id
        }
    }

    private func refreshMyWeatherIfNeeded(force: Bool = false) async {
        guard let city = appModel.currentUser.homeCity else { return }
        guard force || myWeatherFetchedForCityID != city.id else { return }
        if let reading = await TwofoldWeatherService.currentWeather(for: city) {
            myWeatherReading = reading
            myWeatherFetchedForCityID = city.id
        }
    }

    /// Everything `onAppear` does, minus the staleness guards, run as one awaited unit so the
    /// spinner stays up until the screen is actually current rather than snapping back while the
    /// fetches are still in flight.
    private func pullToRefresh() async {
        refreshPendingShares()
        async let everything: Void = appModel.refreshAll()
        async let weather: Void = refreshWeatherIfNeeded(force: true)
        _ = await (everything, weather)
    }

    /// One row of the setup checklist.
    ///
    /// The rows are gathered into a list rather than written as three `if`s inside the stack, so
    /// that the dividers can sit *between* them. Inline conditionals give no way to ask whether a
    /// given row is the first one still showing — and that changes as rows get completed, so it
    /// cannot be hard-coded either.
    private struct ChecklistItem: Identifiable {
        let task: ChecklistTask
        let action: () -> Void
        var id: String { task.rawValue }
    }

    /// The three rows, as cases rather than as strings.
    ///
    /// The titles used to be `String`s on `ChecklistItem`, handed to `Text(title)`. That renders
    /// perfectly and never reaches `Localizable.xcstrings`: Xcode extracts a literal written inside
    /// `Text`, not a `String` variable that arrives there, so these three shipped permanently
    /// untranslated with nothing to indicate it. Same shape as `GatedFeature` in
    /// `SubscriptionRequiredView`, for the same reason.
    private enum ChecklistTask: String {
        case trip
        case flight
        case location

        var title: Text {
            switch self {
            case .trip: Text("Add your next trip")
            case .flight: Text("Add your first flight")
            case .location: Text("Turn on location access")
            }
        }

        /// The icon travels with the case too, so adding a row is one place rather than two.
        var icon: ChecklistIcon {
            switch self {
            case .trip: .system("airplane.departure")
            case .flight: .asset("boarding-pass")
            case .location: .system("location")
            }
        }
    }

    /// Trip and flight rows need a connected partner to make sense — see `setupChecklistCard`,
    /// which uses the same conditions to decide whether the card appears at all.
    private var checklistItems: [ChecklistItem] {
        var items: [ChecklistItem] = []
        if appModel.partnerConnected, appModel.needsFirstTrip {
            items.append(ChecklistItem(task: .trip, action: { showingAddTrip = true }))
        }
        if appModel.partnerConnected, appModel.needsFirstFlight {
            items.append(ChecklistItem(task: .flight, action: { showingAddFlight = true }))
        }
        // Own city only. This row is an instruction to use this device's location permission, so
        // it has no business appearing when the city that is missing is the partner's — see
        // `AppModel.needsOwnHomeCity`.
        if appModel.needsOwnHomeCity {
            items.append(ChecklistItem(task: .location, action: { showingLocationPermission = true }))
        }
        return items
    }

    enum ChecklistIcon {
        case system(String)
        case asset(String)
    }

    private func checklistRow(task: ChecklistTask, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Group {
                    switch task.icon {
                    case .asset(let name):
                        Image(name)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    case .system(let name):
                        Image(systemName: name)
                    }
                }
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

                task.title
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            // A single line of `.subheadline` is around 20pt tall, so these rows were roughly half
            // the 44pt minimum — and the gap between two of them was dead space that looked
            // tappable. `contentShape` also makes the empty stretch between the title and the
            // chevron hit the button, rather than only the text and glyphs themselves.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "500+"/"2000+" — matches `SubscriptionTier.features`' own "N+ questions and games"
    /// copy convention (`Features/Paywall/SubscriptionStore.swift`), so this card promises
    /// exactly what the paywall itself already promises for the couple's current tier.
    private var partnerValuePropGameCount: String {
        appModel.subscriptionTier == "premium" ? "2000+" : "500+"
    }

    /// Someone has already redeemed this user's invite code and is waiting on a decision —
    /// takes over `invitePartnerCard`'s slot entirely rather than showing alongside it ("connect
    /// with your partner" and "someone wants to connect" at once would just be confusing), since
    /// responding to an already-arrived request is strictly more actionable than being pitched
    /// the feature again. Opens the focused `ConnectionRequestReviewView` (just this one
    /// request's avatar/name + Accept/Decline), not the full `PartnerSetupView` profile editor.
    private func pendingConnectionRequestCard(_ request: BackendService.PendingConnectionRequest) -> some View {
        Button {
            reviewingConnectionRequest = request
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(
                        person: Person(
                            id: request.requesterId,
                            name: request.requesterFirstName,
                            accentColor: Person.palette[0],
                            avatarURL: request.requesterAvatarURL
                        ),
                        size: 56,
                        showsRing: true
                    )

                    Text("\(request.requesterFirstName) wants to connect")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                Text("Accept to start sharing trips, flights, and memories together.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Review request")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(Theme.onPrimaryButton)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The *outgoing* counterpart to `pendingConnectionRequestCard` above — I redeemed someone
    /// else's code and I'm the one waiting now. Takes over `invitePartnerCard`'s slot the same
    /// way (already invited someone; being pitched the feature again would be redundant), and
    /// opens the same `PendingConnectionApprovalView` that used to be a full-screen root gate —
    /// now just a status sheet, since there's nothing left to block here.
    private func pendingOutgoingInviteCard(_ request: BackendService.OutgoingConnectionRequest) -> some View {
        Button {
            showingPendingOutgoingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    AvatarView(
                        person: Person(
                            id: request.inviterId,
                            name: request.inviterFirstName,
                            accentColor: Person.palette[0],
                            avatarURL: request.inviterAvatarURL
                        ),
                        size: 56,
                        showsRing: true
                    )

                    Text("Invite pending with \(request.inviterFirstName)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }

                Text("They haven't accepted yet — feel free to explore Twofold while you wait, or send them a nudge.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("View status")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(Theme.onPrimaryButton)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The prominent, primary prompt whenever there's no connected partner — pulled out of
    /// `setupChecklistCard` into its own full-weight card (rather than a small checklist row)
    /// since setting up a partner is a much bigger, more central action than the other
    /// checklist items, and opens a single focused screen covering name/photo/city/anniversary
    /// plus the actual connect step, instead of splitting that across two separate rows.
    ///
    /// Deliberately its own bold blue-gradient design (not another pale `SectionCard`) — this is
    /// the single highest-value action a solo user can take, so it gets real visual weight and
    /// copy that actually sells why, instead of reading as just another checklist item.
    private var invitePartnerCard: some View {
        Button {
            showingPartnerSetup = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(.white.opacity(0.2))
                        Image(systemName: "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                    .frame(width: 56, height: 56)

                    Text("Set up your partner")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer(minLength: 0)
                }

                Text("Twofold is built for couples. Connect with your partner to unlock \(partnerValuePropGameCount) questions and games, track each other's flights, and add shared trips and memories.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text("Get started")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(Theme.onPrimaryButton)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryButtonGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var homeCityPromptCard: some View {
        SectionCard {
            Button {
                showingLocationPermission = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See the distance between you")
                            .font(.headline)
                        Text("Turn on location access to light up the map.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "map").foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Shown when the only missing city is the partner's.
    ///
    /// Deliberately not a button. `homeCityPromptCard`'s tap opens the location permission screen,
    /// which sets *this* device's city — offering it here would ask somebody to grant a permission
    /// they have already granted, and leave the map exactly as dark afterwards.
    private var partnerHomeCityPendingCard: some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See the distance between you")
                        .font(.headline)
                    Text("\(appModel.partner.name) needs to turn on location access before the map can light up.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                // Subdued rather than `accent`: nothing here is tappable, and the accent colour
                // is what tells the rest of this screen that something is.
                Image(systemName: "map").foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func sameCityCard(city: Place) -> some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Same city")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("You're both in \(city.displayCity)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.coral)
            }
            Text("No distance to close right now")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func distanceCard(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance between you")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(MeasurementPreference.distanceLabel(km: distanceKm))
                        .font(.system(size: 36, weight: .bold))
                        .tracking(-1)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                CircularNavButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share distance") {
                    distanceShareContext = DistanceShareContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
                }
            }
            // Hidden below 0.05% — anything less rounds to a deadpan, uninformative "0.0%" at
            // this line's own one-decimal precision (nearby but not exactly the same city, e.g.,
            // still shows the real km figure above just fine, but "that's 0.0% of the way around
            // the earth" reads as a bug, not a fact).
            if Geo.percentOfEarthCircumference(distanceKm) >= 0.05 {
                Text("\(Geo.percentOfEarthCircumference(distanceKm), format: .number.precision(.fractionLength(1)))% of the way around the Earth")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }

            RelationshipGlobeView(couple: appModel.couple, partnerACity: myCity, partnerBCity: partnerCity, activeTrip: appModel.activeTrip)
                .frame(height: 260)
                // A preview, not a globe you turn here. Two reasons, and the first one predates
                // this card being tappable at all: a live `Map` inside a `ScrollView` competes for
                // every drag, so a swipe that meant "scroll Home" as often nudged the earth
                // instead. The second is that the tap below has to reach the card, and a `Map`
                // consumes taps whether or not it does anything with them. Turning it is what the
                // full-screen view exists for.
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.image, style: .continuous))
                // Added after `allowsHitTesting(false)`, so the badge is a sibling layered on top
                // of the inert map and takes taps normally. Order matters here: modifying the map
                // first and overlaying second is what keeps the button live.
                .overlay(alignment: .topTrailing) {
                    CircularNavButton(systemImage: "arrow.up.left.and.arrow.down.right", accessibilityLabel: "See the globe full screen") {
                        globeFullScreenContext = GlobeFullScreenContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
                    }
                    .padding(Theme.Spacing.sm)
                }
        }
        // The whole card, as asked. The share button keeps its own taps — it's a `Button`, so it
        // is hit first — and the globe above is inert by the time this gesture sees anything.
        .contentShape(Rectangle())
        .onTapGesture {
            globeFullScreenContext = GlobeFullScreenContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
        }
    }

    /// Swipeable, one-card-per-page carousel when tracking more than one flight — `flights` is
    /// already sorted soonest-departure-first by `AppModel.activeOrUpcomingFlights`. Falls back
    /// to a single plain card (no paging chrome) when there's just one, since a carousel of one
    /// page (and a single dot) reads oddly.
    private func flightCarousel(flights: [Flight]) -> some View {
        Group {
            if flights.count == 1 {
                NavigationLink {
                    FlightTrackingView(flight: flights[0])
                } label: {
                    activeFlightCard(flight: flights[0])
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
                                    activeFlightCard(flight: flight)
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
                    .scrollPosition(id: $flightCarouselPage)

                    HStack(spacing: 6) {
                        ForEach(flights) { flight in
                            Circle()
                                .fill(flight.id == (flightCarouselPage ?? flights.first?.id) ? Theme.accent : Theme.textSecondary.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: flightCarouselPage)
                }
            }
        }
    }

    /// A live, AeroAPI-backed flight (or a self-reported one — either way, whatever
    /// `Flight` actually has) — supersedes `nextReunionCard` whenever one exists, since it
    /// carries real status/countdown instead of just a trip's planned dates.
    private func activeFlightCard(flight: Flight) -> some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.status.isActivelyTracked ? "Tracking now" : "Next flight")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Theme.Spacing.xs) {
                        // 24pt, not 18 — at 18pt, .scaledToFill() cropping a wide tailfin logo
                        // into a near-square frame was cutting away most of the actual mark,
                        // reading as "no logo" even though it was technically rendering.
                        AirlineLogoView(url: flight.displayLogoURL, size: 24)
                        Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " "))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                StatusPill(flight: flight)
            }

            // The route as airport codes, 30pt bold (section 6, Home): "FCO → SFO". Codes are short
            // and fixed-width enough that the line never needs to shrink.
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(flight.origin.displayCode)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .bold))
                        .accessibilityLabel("to")
                    Text(flight.destination.displayCode)
                }
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                if let totalDurationSummary = flight.totalDurationSummary {
                    Text(totalDurationSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            HStack(alignment: .center) {
                Text(flight.countdownSummary)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: Theme.Spacing.sm)

                // Port + local time for each end, stacked (not side by side) — a long-format
                // arrival time was pushing departure onto a second row when both fought for the
                // same line. Departure in the origin's timezone, arrival in the destination's,
                // same convention FlightTrackingView's journey rows use.
                VStack(alignment: .trailing, spacing: 3) {
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

    /// Joins the resolvable names for a trip's travelers ("Alex" / "Alex & You") — falls back to
    /// `appModel.partner.name` for the (common) case of a single unresolvable/placeholder id,
    /// same fallback the old single-`travelerID` code used.
    private func travelerNames(_ ids: [Person.ID]) -> String {
        let names = ids.compactMap { appModel.couple.partner($0)?.name }
        guard !names.isEmpty else { return appModel.partner.name }
        return names.joined(separator: " & ")
    }

    /// The card above the fold: a countdown to the next trip, or — once one is under way — the fact
    /// that it is.
    ///
    /// The under-way case used to be unreachable here. `upcomingTrips` includes active trips, but
    /// `Trip.isActive` only returned true while an attached flight was in the air, so a trip with
    /// no tracked flight counted as past the moment it began and never reached this card. Once
    /// that was fixed, the card started showing in-progress trips and its copy did not fit them:
    /// it counts down to `departureDate`, which is behind you mid-trip, so a `max(0, …)` clamp
    /// pinned the count at zero and announced "Next reunion — Today" on day four of a visit.
    ///
    /// The clamp is gone with it. `upcomingTrips` is `isUpcoming || isActive`, and `isUpcoming` is
    /// `departureDate > .now`, so the only trips that now reach the countdown have a departure
    /// strictly ahead of them and `daysUntil` — which counts calendar days — cannot go negative.
    /// The sibling call sites in TripRowView, TripsCarouselCards and RelationshipMilestoneStats
    /// keep theirs: those are reached by past trips too.
    ///
    /// Deliberately not a countdown to the end. The remaining days are knowable — `arrivalDate` is
    /// right there — but putting a timer on a visit turns the good half of a long-distance
    /// relationship into a countdown to the goodbye.
    /// Who is going where, in the tense that matches whether it has happened yet.
    ///
    /// `.solo` names the traveller because only one of them is moving and which one matters. The
    /// other categories do not: both are already "your trip together", and naming a traveller on a
    /// trip they are taking jointly would read as though the other were being left behind.
    private func tripSubtitle(_ trip: Trip) -> String {
        guard trip.category == .solo else {
            return trip.isActive ? "You're together now" : "Your trip together"
        }
        let names = travelerNames(trip.travelerIDs)
        let plural = trip.travelerIDs.count > 1
        if trip.isActive {
            return plural ? "\(names) are with you" : "\(names) is with you"
        }
        return plural ? "\(names) fly to you" : "\(names) flies to you"
    }

    private func nextReunionCard(trip: Trip) -> some View {
        let daysToGo = TimeMath.daysUntil(trip.departureDate)
        return SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.isActive ? "Right now" : "Next reunion")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(trip.isActive ? "Together 💛" : (daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go"))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.coral)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Past tense once they have gone. "Max flies to you" is a promise, and reading
                    // it on day four of the visit makes the app look like it has not noticed.
                    Text(tripSubtitle(trip))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    let route = trip.routeEndpoints
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(route.origin)
                        Image(systemName: "arrow.right")
                        Text(route.destination)
                    }
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    if let flight = trip.mostRelevantFlight {
                        Text("\(trip.departureDate, format: .dateTime.day().month(.abbreviated)) · \(flight.flightNumber)")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(Theme.accentFill)
                    Image(systemName: "airplane")
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AppModel())
}
