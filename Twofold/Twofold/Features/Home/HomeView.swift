//
//  GlobeHomeView.swift
//  Twofold
//

import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSnapshot = false
    @State private var showingSettings = false
    @State private var showingPartnerSetup = false
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
    @AppStorage("setupChecklistDismissed") private var setupChecklistDismissed = false

    private var distanceKm: Double? {
        guard let mine = appModel.currentUser.homeCity?.coordinate, let theirs = appModel.partner.homeCity?.coordinate else { return nil }
        return Geo.distanceKm(mine, theirs)
    }

    private var sameCity: Bool {
        guard let mine = appModel.currentUser.homeCity, let theirs = appModel.partner.homeCity else { return false }
        return mine.city == theirs.city && mine.country == theirs.country
    }

    private var soonestTrip: Trip? {
        appModel.upcomingTrips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    if appModel.needsPartnerInvite {
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
                            cityName: appModel.partner.homeCity?.city,
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
                    } else {
                        homeCityPromptCard
                    }
                    if appModel.partnerConnected {
                        DrawingPadCard()
                        RecommendedGamesSection()
                    }
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
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        AvatarView(person: appModel.currentUser, size: 30)
                        Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed).font(.caption)
                        AvatarView(person: appModel.partner, size: 30)
                    }
                }
            }
            .sheet(item: $reviewingShare, onDismiss: refreshPendingShares) { share in
                PendingFlightShareReviewView(share: share)
            }
            .onAppear {
                refreshPendingShares()
                Task { await appModel.refreshCoupleStateIfNeeded() }
                Task { await appModel.refreshFlights() }
                Task { await refreshWeatherIfNeeded() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshPendingShares()
                    Task { await appModel.refreshCoupleStateIfNeeded() }
                    Task { await appModel.refreshFlights() }
                    Task { await refreshWeatherIfNeeded() }
                }
            }
            .sheet(isPresented: $showingSnapshot) { SnapshotShareView() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingLocationPermission) { NavigationStack { LocationPermissionView() } }
            .sheet(isPresented: $showingAddFlight) { AddFlightView() }
            .sheet(isPresented: $showingPartnerSetup) {
                PartnerSetupView()
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
        }
    }

    @ViewBuilder
    private var setupChecklistCard: some View {
        if !setupChecklistDismissed && (appModel.needsFirstTrip || appModel.needsFirstFlight || appModel.needsHomeCities) {
            SectionCard {
                HStack {
                    Text("Finish setting up Twofold")
                        .font(.headline)
                    Spacer()
                    Button {
                        setupChecklistDismissed = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.subtleInk.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                if appModel.needsFirstTrip {
                    checklistRow(icon: .system("airplane.departure"), title: "Add your next trip") { showingAddTrip = true }
                }
                if appModel.needsFirstFlight {
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
        }
        .buttonStyle(.plain)
    }

    /// The prominent, primary prompt whenever there's no connected partner — pulled out of
    /// `setupChecklistCard` into its own full-weight card (rather than a small checklist row)
    /// since setting up a partner is a much bigger, more central action than the other
    /// checklist items, and opens a single focused screen covering name/photo/city/anniversary
    /// plus the actual connect step, instead of splitting that across two separate rows.
    private var invitePartnerCard: some View {
        Button {
            showingPartnerSetup = true
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(Theme.skyBlue.opacity(0.15))
                        Image(systemName: "person.2.fill").foregroundStyle(Theme.skyBlue)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set up your partner")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Add their name and photo, then connect with an invite code.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
            }
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
                    Text("You're both in \(city.city)")
                        .font(.title3.weight(.bold))
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.heartRed)
            }
            Text("No distance to close right now 💛")
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
                    showingSnapshot = true
                } label: {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.skyBlue)
                }
            }
            Text("That's \(Geo.percentOfEarthCircumference(distanceKm), format: .number.precision(.fractionLength(1)))% of the way around the earth 🌍")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)

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
                    }
                }
                Spacer()
                PillBadge(text: flight.status.displayLabel, tint: flight.status.semanticColor)
            }

            HStack(spacing: Theme.Spacing.xs) {
                Text(flight.origin.displayCode)
                Image(systemName: "arrow.right")
                Text(flight.destination.displayCode)
            }
            .font(.title3.weight(.bold))

            Text(flight.countdownSummary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.skyBlue)

            GeometryReader { proxy in
                let iconSize: CGFloat = 30
                let progressWidth = proxy.size.width * flight.progress
                // Keeps the icon's center on the track even at the very start/end, where it
                // would otherwise hang half off the edge of the bar.
                let iconCenterX = min(max(progressWidth, iconSize / 2), proxy.size.width - iconSize / 2)

                Capsule().fill(Theme.skyBlue.opacity(0.15)).frame(height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(flight.status.semanticColor).frame(width: progressWidth, height: 5)
                    }
                    .overlay(alignment: .leading) {
                        ZStack {
                            Circle().fill(.white)
                            // SF Symbols' "airplane" glyph already points due right (east) at
                            // rotation 0 — no rotation needed to lie flat along the track.
                            Image(systemName: "airplane")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(flight.status.semanticColor)
                        }
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                        .offset(x: iconCenterX - iconSize / 2)
                    }
            }
            .frame(height: 30)

            // Unconditional, not gated behind isActivelyTracked — FlightTrackingView already
            // shows this map for any flight regardless of status (FlightMapView has its own
            // graceful fallback for missing coordinates), so a merely-.scheduled flight on Home
            // was the one place showing no map at all, reading as a bug rather than by-design.
            FlightMapView(flight: flight, interactive: false, edgePadding: 28)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .allowsHitTesting(false)
        }
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
                    Text("\(appModel.couple.partner(trip.travelerID)?.name ?? appModel.partner.name) flies to you")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(trip.origin.iataCode ?? trip.origin.city)
                        Image(systemName: "arrow.right")
                        Text(trip.destination.iataCode ?? trip.destination.city)
                    }
                    .font(.headline)

                    if let flight = trip.flight {
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
