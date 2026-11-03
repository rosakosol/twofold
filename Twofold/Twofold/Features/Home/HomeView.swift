//
//  HomeView.swift
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
        appModel.travel.upcomingTrips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    statusCards
                    timeZoneCard
                    travelCard
                    distanceCard
                    drawingPadCard
                    gamesSection
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
                        partner: appModel.session.partnerConnected ? appModel.partner : nil,
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
                Task { await appModel.travel.refreshTrips() }
                Task { await appModel.travel.refreshFlights() }
                Task { await appModel.travel.refreshMemories() }
                Task { await refreshWeatherIfNeeded() }
                if appModel.needsPartnerInvite {
                    Task { await appModel.session.refreshPendingConnectionRequests() }
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
                    Task { await appModel.travel.refreshFlights() }
                    Task { await refreshWeatherIfNeeded() }
                    if appModel.needsPartnerInvite {
                        Task { await appModel.session.refreshPendingConnectionRequests() }
                    }
                }
            }
            .sheet(item: $distanceShareContext) { context in
                DistanceShareView(couple: appModel.session.couple, myCity: context.myCity, partnerCity: context.partnerCity, distanceKm: context.distanceKm)
            }
            // A cover rather than a sheet: a sheet keeps Home's cards visible behind a rounded
            // card of its own, and this is a globe you turn — the grabber and the inset edges
            // would both be things to catch a drag meant for the earth.
            .fullScreenCover(item: $globeFullScreenContext) { context in
                RelationshipGlobeFullScreenView(
                    couple: appModel.session.couple,
                    myCity: context.myCity,
                    partnerCity: context.partnerCity,
                    activeTrip: appModel.travel.activeTrip,
                    distanceKm: context.distanceKm
                )
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingLocationPermission) { NavigationStack { LocationPermissionView() } }
            .addContentSheet(isPresented: $showingAddFlight, canAdd: appModel.subscription.canAddContent, feature: .flights) { AddFlightView() }
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
                if let request = appModel.session.pendingOutgoingConnectionRequest {
                    PendingConnectionApprovalView(request: request)
                }
            }
            .addContentSheet(isPresented: $showingAddTrip, canAdd: appModel.subscription.canAddContent, feature: .trips) {
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
            .onChange(of: appModel.prompts.partnerDisconnectedMessage) { _, newValue in
                guard let newValue else { return }
                partnerDisconnectedAlert = newValue
                appModel.prompts.partnerDisconnectedMessage = nil
            }
            // Reconnecting retires the notice. The message is copied into local state above and
            // the model's copy cleared immediately, so clearing the model on re-adopt cannot
            // dismiss an alert that has already been taken — leaving "your connection with X has
            // ended" sitting over a Home screen that was showing the new couple.
            .onChange(of: appModel.session.partnerConnected) { _, isConnected in
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

    // MARK: - Cards

    /// The cards that ask for something: a lapsed subscription, the partner's status, the setup
    /// checklist, flight shares waiting for review. Each draws nothing when there is nothing to ask.
    @ViewBuilder
    private var statusCards: some View {
        // Neither card is dismissable, so the subscription state is what takes them
        // away: resubscribing clears both without anything having to be acknowledged.
        // Nested rather than two sibling conditions so the lapsed card cannot outlive
        // the situation it describes.
        // Waits to be told, rather than assuming the worst while it finds out.
        // `canAddContent` is false before the first answer lands as well as when
        // somebody genuinely has not paid, and rendering the second on the way to the
        // first flashed "No active subscription" at a paying subscriber on every
        // launch. Same shape as the invite card in `PartnerStatusSection` below, and for the same reason: no
        // card is better than the wrong one, and the gap is one round trip.
        if appModel.subscription.hasResolved, !appModel.subscription.canAddContent {
            if let lapsedPartnerName = appModel.prompts.partnerSubscriptionLapsedPartnerName {
                // The specific reason, when there is one. Shown instead of the general
                // card rather than as well as it — two cards saying "you have no
                // subscription" one above the other is noise, and this one says more.
                SubscriptionLapsedCard(partnerName: lapsedPartnerName, onSeePlans: { showingPaywall = true })
            } else {
                NoSubscriptionCard(onSeePlans: { showingPaywall = true })
            }
        }

        PartnerStatusSection(
            onReviewRequest: { reviewingConnectionRequest = $0 },
            onShowOutgoingRequest: { showingPendingOutgoingDetail = true },
            onSetUpPartner: { showingPartnerSetup = true }
        )
        SetupChecklistCard(
            onAddTrip: { showingAddTrip = true },
            onAddFlight: { showingAddFlight = true },
            onTurnOnLocation: { showingLocationPermission = true }
        )
        PendingSharesCard(shares: pendingShares, onReview: { reviewingShare = $0 })
    }

    @ViewBuilder
    private var timeZoneCard: some View {
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
    }

    /// The next flight, or failing that the next trip.
    @ViewBuilder
    private var travelCard: some View {
        if !appModel.travel.activeOrUpcomingFlights.isEmpty {
            HomeFlightCarousel(flights: appModel.travel.activeOrUpcomingFlights, page: $flightCarouselPage)
        } else if let soonestTrip {
            NextReunionCard(trip: soonestTrip)
        }
    }

    @ViewBuilder
    private var distanceCard: some View {
        if let myCity = appModel.currentUser.homeCity, let partnerCity = appModel.partner.homeCity {
            if sameCity {
                SameCityCard(city: myCity)
            } else if let distanceKm {
                DistanceCard(
                    distanceKm: distanceKm,
                    myCity: myCity,
                    partnerCity: partnerCity,
                    onShare: {
                        distanceShareContext = DistanceShareContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
                    },
                    onOpenGlobe: {
                        globeFullScreenContext = GlobeFullScreenContext(myCity: myCity, partnerCity: partnerCity, distanceKm: distanceKm)
                    }
                )
            }
        } else if appModel.session.hasLoadedCoupleState, appModel.needsOwnHomeCity {
            HomeCityPromptCard(onTap: { showingLocationPermission = true })
        } else if appModel.session.hasLoadedCoupleState, appModel.needsPartnerHomeCity {
            PartnerHomeCityPendingCard()
        }
        // Nothing in the remaining case — a solo user who has set their own city. There
        // is no distance to show and nobody to wait on, and `PartnerStatusSection` above
        // already owns the "connect with someone" prompt.
    }

    @ViewBuilder
    private var drawingPadCard: some View {
        if appModel.session.partnerConnected {
            DrawingPadCard()
        }
    }

    private var gamesSection: some View {
        RecommendedGamesSection(onSeeAllGames: onSeeAllGames)
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
}

#Preview {
    HomeView()
        .environment(AppModel())
}
