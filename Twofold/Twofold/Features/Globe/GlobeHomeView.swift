//
//  GlobeHomeView.swift
//  Twofold
//

import SwiftUI

struct GlobeHomeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSnapshot = false
    @State private var showingSettings = false
    @State private var showingInvite = false
    @State private var showingRedeemCode = false
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    @State private var showingHomeCities = false
    @State private var pendingShares: [PendingFlightShare] = []
    @State private var reviewingShare: PendingFlightShare?
    @State private var weatherReading: CurrentWeatherReading?
    @State private var weatherFetchedForCityID: UUID?

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
                    setupChecklistCard
                    pendingSharesCard
                    if let partnerTimeZone = appModel.partner.homeCity?.timeZone {
                        TimeZoneCard(
                            person: appModel.partner,
                            timeZone: partnerTimeZone,
                            comparisonTimeZone: appModel.currentUser.homeCity?.timeZone,
                            sameCity: sameCity,
                            cityName: appModel.partner.homeCity?.city,
                            weather: weatherReading
                        )
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
                    if let flight = appModel.activeOrUpcomingFlight {
                        NavigationLink {
                            FlightTrackingView(flight: flight)
                        } label: {
                            activeFlightCard(flight: flight)
                        }
                        .buttonStyle(.plain)
                    } else if let soonestTrip {
                        nextReunionCard(trip: soonestTrip)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        AvatarView(person: appModel.currentUser, size: 30)
                        Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed).font(.caption)
                        AvatarView(person: appModel.partner, size: 30)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSnapshot = true
                    } label: {
                        Image(systemName: "bell")
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
            .sheet(isPresented: $showingHomeCities) { HomeCitiesView() }
            .sheet(isPresented: $showingAddFlight) { AddFlightView() }
            .sheet(isPresented: $showingInvite) {
                NavigationStack {
                    ShareInviteView(code: appModel.inviteCode ?? "") {
                        showingInvite = false
                    }
                }
            }
            .sheet(isPresented: $showingRedeemCode) {
                RedeemPartnerCodeView()
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
        if appModel.needsPartnerInvite || appModel.needsFirstTrip || appModel.needsFirstFlight || appModel.needsHomeCities {
            SectionCard {
                Text("Finish setting up Twofold")
                    .font(.headline)

                if appModel.needsPartnerInvite {
                    checklistRow(icon: .system("person.badge.plus"), title: "Invite \(appModel.partner.name) to finish setting up Twofold") {
                        Task {
                            if appModel.inviteCode == nil {
                                appModel.inviteCode = try? await BackendService.createInviteCode(firstName: appModel.currentUser.name)
                            }
                            if appModel.inviteCode != nil {
                                showingInvite = true
                            }
                        }
                    }
                }
                if appModel.needsPartnerInvite {
                    checklistRow(icon: .system("person.fill.checkmark"), title: "Have a code from \(appModel.partner.name)? Enter it") {
                        showingRedeemCode = true
                    }
                }
                if appModel.needsFirstTrip {
                    checklistRow(icon: .system("airplane.departure"), title: "Add your next trip") { showingAddTrip = true }
                }
                if appModel.needsFirstFlight {
                    checklistRow(icon: .asset("boarding-pass"), title: "Add your first flight") { showingAddFlight = true }
                }
                if appModel.needsHomeCities {
                    checklistRow(icon: .system("house"), title: "Set your home cities") { showingHomeCities = true }
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
    /// and the time card only needs a fresh reading roughly hourly, not on every foreground.
    private func refreshWeatherIfNeeded() async {
        guard let city = appModel.partner.homeCity else { return }
        guard weatherFetchedForCityID != city.id else { return }
        weatherFetchedForCityID = city.id
        weatherReading = await TwofoldWeatherService.currentWeather(for: city)
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

    private var homeCityPromptCard: some View {
        SectionCard {
            Button {
                showingHomeCities = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See the distance between you")
                            .font(.headline)
                        Text("Set your home cities to light up the map.")
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
                    Text("\(distanceKm.formatted(.number.precision(.fractionLength(0)))) km")
                        .font(.title.weight(.bold))
                }
                Spacer()
                Button {
                    showingSnapshot = true
                } label: {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.title2)
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
                        AirlineLogoView(url: flight.displayLogoURL, size: 18)
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
                Capsule().fill(Theme.skyBlue.opacity(0.15)).frame(height: 5)
                    .overlay(alignment: .leading) {
                        Capsule().fill(flight.status.semanticColor).frame(width: proxy.size.width * flight.progress, height: 5)
                    }
            }
            .frame(height: 5)

            if flight.status.isActivelyTracked {
                FlightMapView(flight: flight, interactive: false)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .allowsHitTesting(false)
            }
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
    GlobeHomeView()
        .environment(AppModel())
}
