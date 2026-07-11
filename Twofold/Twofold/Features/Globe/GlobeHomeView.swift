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
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    @State private var showingHomeCities = false
    @State private var pendingShares: [PendingFlightShare] = []
    @State private var reviewingShare: PendingFlightShare?

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
                            sameCity: sameCity
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
                    if let soonestTrip {
                        NavigationLink {
                            FlightTrackingView(trip: soonestTrip)
                        } label: {
                            nextReunionCard(trip: soonestTrip)
                        }
                        .buttonStyle(.plain)
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
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    refreshPendingShares()
                    Task { await appModel.refreshCoupleStateIfNeeded() }
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
                    checklistRow(icon: "person.badge.plus", title: "Invite \(appModel.partner.name) to finish setting up Twofold") {
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
                if appModel.needsFirstTrip {
                    checklistRow(icon: "airplane.departure", title: "Add your next trip") { showingAddTrip = true }
                }
                if appModel.needsFirstFlight {
                    checklistRow(icon: "ticket", title: "Add your first flight") { showingAddFlight = true }
                }
                if appModel.needsHomeCities {
                    checklistRow(icon: "house", title: "Set your home cities") { showingHomeCities = true }
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

    private func checklistRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).foregroundStyle(Theme.skyBlue).frame(width: 24)
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
            Text("No distance to close right now - make the most of being together 💛")
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
