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

struct HomeView: View {
    /// Set by `MainTabView` to flip its own tab selection to Games, passed straight through to
    /// `RecommendedGamesSection`'s "See all games" — defaults to a no-op so the preview below
    /// still compiles.
    var onSeeAllGames: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSnapshot = false
    @State private var distanceShareContext: DistanceShareContext?
    @State private var showingSettings = false
    @State private var showingPartnerSetup = false
    @State private var reviewingConnectionRequest: BackendService.PendingConnectionRequest?
    @State private var showingPendingOutgoingDetail = false
    @State private var showingAddTrip = false
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
                    if let incomingRequest = appModel.pendingConnectionRequests.first {
                        pendingConnectionRequestCard(incomingRequest)
                    } else if let outgoingRequest = appModel.pendingOutgoingConnectionRequest {
                        pendingOutgoingInviteCard(outgoingRequest)
                    } else if appModel.needsPartnerInvite {
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
                        // Required wherever WeatherKit data is shown, so it's tied to a reading
                        // actually being on screen rather than to the card — the card renders with
                        // no temperature at all until WeatherKit answers (or if the capability
                        // isn't enabled), and there's nothing to attribute in that state.
                        if weatherReading != nil || myWeatherReading != nil {
                            WeatherAttributionView()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
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
                    } else {
                        homeCityPromptCard
                    }
                    if appModel.partnerConnected {
                        DrawingPadCard()
                    }
                    RecommendedGamesSection(onSeeAllGames: onSeeAllGames)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        AvatarView(person: appModel.currentUser, size: 30)
                        Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed).font(.caption)
                        AvatarView(person: appModel.partner, size: 30)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(appModel.partnerConnected ? "\(appModel.currentUser.name) and \(appModel.partner.name)" : appModel.currentUser.name)
                }
            }
            .sheet(item: $reviewingShare, onDismiss: refreshPendingShares) { share in
                PendingFlightShareReviewView(share: share)
            }
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
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingLocationPermission) { NavigationStack { LocationPermissionView() } }
            .sheet(isPresented: $showingAddFlight) { AddFlightView() }
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
            .onChange(of: appModel.partnerDisconnectedMessage) { _, newValue in
                guard let newValue else { return }
                partnerDisconnectedAlert = newValue
                appModel.partnerDisconnectedMessage = nil
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

    @ViewBuilder
    private var setupChecklistCard: some View {
        // Trip/flight rows need a connected partner to make sense — the dedicated
        // `invitePartnerCard` above already owns that prompt, so this checklist only ever shows
        // those two rows once a partner exists. "Turn on location access" is independent of
        // partner status and still shows regardless.
        let showsTripOrFlightRow = appModel.partnerConnected && (appModel.needsFirstTrip || appModel.needsFirstFlight)
        if !appModel.setupChecklistDismissed && (showsTripOrFlightRow || appModel.needsHomeCities) {
            SectionCard {
                HStack {
                    Text("Finish setting up Twofold")
                        .font(.headline)
                    Spacer()
                    Button {
                        appModel.dismissSetupChecklist()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.subtleInk.opacity(0.5))
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

                if appModel.partnerConnected, appModel.needsFirstTrip {
                    checklistRow(icon: .system("airplane.departure"), title: "Add your next trip") { showingAddTrip = true }
                }
                if appModel.partnerConnected, appModel.needsFirstFlight {
                    checklistRow(icon: .asset("boarding-pass"), title: "Add your first flight") { showingAddFlight = true }
                }
                if appModel.needsHomeCities {
                    checklistRow(icon: .system("location"), title: "Turn on location access") { showingLocationPermission = true }
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
                            Circle().fill(Theme.skyBlue.opacity(0.15))
                            Image(systemName: "envelope.badge").foregroundStyle(Theme.skyBlue)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pendingShares.count == 1 ? "1 flight email to review" : "\(pendingShares.count) flight emails to review")
                                .font(.headline)
                            Text("Shared from Mail — tap to add the flight")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
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
    private func refreshWeatherIfNeeded() async {
        async let partner: Void = refreshPartnerWeatherIfNeeded()
        async let mine: Void = refreshMyWeatherIfNeeded()
        _ = await (partner, mine)
    }

    private func refreshPartnerWeatherIfNeeded() async {
        guard let city = appModel.partner.homeCity else { return }
        guard weatherFetchedForCityID != city.id else { return }
        if let reading = await TwofoldWeatherService.currentWeather(for: city) {
            weatherReading = reading
            weatherFetchedForCityID = city.id
        }
    }

    private func refreshMyWeatherIfNeeded() async {
        guard let city = appModel.currentUser.homeCity else { return }
        guard myWeatherFetchedForCityID != city.id else { return }
        if let reading = await TwofoldWeatherService.currentWeather(for: city) {
            myWeatherReading = reading
            myWeatherFetchedForCityID = city.id
        }
    }
    
    enum ChecklistIcon {
        case system(String)
        case asset(String)
    }

    private func checklistRow(icon: ChecklistIcon, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Group {
                    switch icon {
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
                .foregroundStyle(Theme.skyBlue)
                .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
                .foregroundStyle(.white)
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
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer()
                    Image(systemName: "map").foregroundStyle(Theme.skyBlue)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func sameCityCard(city: Place) -> some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SAME CITY")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text("You're both in \(city.displayCity)")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.heartRed)
            }
            Text("No distance to close right now")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private func distanceCard(distanceKm: Double, myCity: Place, partnerCity: Place) -> some View {
        SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DISTANCE BETWEEN YOU")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Text(MeasurementPreference.distanceLabel(km: distanceKm))
                        .font(.title.weight(.bold))
                }
                Spacer()
                Button {
                    distanceShareContext = DistanceShareContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
                } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.skyBlue)
                }
                .accessibilityLabel("Share distance")
            }
            // Hidden below 0.05% — anything less rounds to a deadpan, uninformative "0.0%" at
            // this line's own one-decimal precision (nearby but not exactly the same city, e.g.,
            // still shows the real km figure above just fine, but "that's 0.0% of the way around
            // the earth" reads as a bug, not a fact).
            if Geo.percentOfEarthCircumference(distanceKm) >= 0.05 {
                Text("That's \(Geo.percentOfEarthCircumference(distanceKm), format: .number.precision(.fractionLength(1)))% of the way around the earth 🌍")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }

            RelationshipGlobeView(couple: appModel.couple, partnerACity: myCity, partnerBCity: partnerCity, activeTrip: appModel.activeTrip)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
                                .fill(flight.id == (flightCarouselPage ?? flights.first?.id) ? Theme.skyBlue : Theme.subtleInk.opacity(0.25))
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
                    Text(flight.status.isActivelyTracked ? "TRACKING NOW" : "NEXT FLIGHT")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    HStack(spacing: Theme.Spacing.xs) {
                        // 24pt, not 18 — at 18pt, .scaledToFill() cropping a wide tailfin logo
                        // into a near-square frame was cutting away most of the actual mark,
                        // reading as "no logo" even though it was technically rendering.
                        AirlineLogoView(url: flight.displayLogoURL, size: 24)
                        Text([flight.airlineName, flight.displayNumber].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                Spacer()
                PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
            }

            // No minimumScaleFactor here — cities stay a fixed size regardless of name length;
            // a long pair truncates with an ellipsis instead of shrinking the whole row.
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(flight.origin.displayName)
                    Image(systemName: "arrow.right")
                    Text(flight.destination.displayName)
                }
                .font(.title3.weight(.bold))
                .lineLimit(1)

                Spacer(minLength: Theme.Spacing.sm)

                if let totalDurationSummary = flight.totalDurationSummary {
                    Text(totalDurationSummary)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            HStack(alignment: .center) {
                Text(flight.countdownSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.skyBlue)
                    .lineLimit(1)

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
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    /// A departure/arrival glyph + airport code + its local time — "—" when the time isn't
    /// known yet rather than omitting the row, so the pair always lines up evenly.
    private func portTimeRow(icon: String, code: String, time: Date?, timeZone: TimeZone?) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2).foregroundStyle(Theme.subtleInk)
            Text(code).font(.caption.weight(.semibold)).lineLimit(1)
            Text(time.map { $0.formatted(Date.FormatStyle(timeZone: timeZone ?? .current).hour().minute()) } ?? "—")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
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

    private func nextReunionCard(trip: Trip) -> some View {
        let daysToGo = max(0, Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0)
        return SectionCard {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next reunion")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                    Text(daysToGo == 0 ? "Today 💛" : "\(daysToGo) days to go")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .foregroundStyle(Theme.heartRed)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.category == .solo ? "\(travelerNames(trip.travelerIDs)) \(trip.travelerIDs.count > 1 ? "fly" : "flies") to you" : "Your trip together")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
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
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                Spacer()
                ZStack {
                    Circle().fill(Theme.skyBlue)
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
