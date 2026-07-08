//
//  GlobeHomeView.swift
//  Twofold
//

import SwiftUI

struct GlobeHomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingSnapshot = false
    @State private var showingPaywall = false
    @State private var showingInvite = false
    @State private var showingAddTrip = false
    @State private var showingAddFlight = false
    @State private var showingHomeCities = false

    private var distanceKm: Double? {
        guard let mine = appModel.currentUser.homeCity?.coordinate, let theirs = appModel.partner.homeCity?.coordinate else { return nil }
        return Geo.distanceKm(mine, theirs)
    }

    private var soonestTrip: Trip? {
        appModel.upcomingTrips.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    setupChecklistCard
                    if let partnerTimeZone = appModel.partner.homeCity?.timeZone {
                        TimeZoneCard(
                            person: appModel.partner,
                            timeZone: partnerTimeZone,
                            comparisonTimeZone: appModel.currentUser.homeCity?.timeZone
                        )
                    }
                    if let myCity = appModel.currentUser.homeCity, let partnerCity = appModel.partner.homeCity, let distanceKm {
                        distanceCard(distanceKm: distanceKm, myCity: myCity, partnerCity: partnerCity)
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
                    Menu {
                        Button("Manage subscription", systemImage: "star.fill") { showingPaywall = true }
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
            .sheet(isPresented: $showingSnapshot) { SnapshotShareView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $showingHomeCities) { HomeCitiesView() }
            .sheet(isPresented: $showingAddFlight) { AddFlightView() }
            .sheet(isPresented: $showingInvite) {
                NavigationStack {
                    ShareInviteView(code: appModel.inviteCode ?? InviteCode.generate(firstName: appModel.currentUser.name)) {
                        appModel.partnerConnected = true
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
                        appModel.inviteCode = appModel.inviteCode ?? InviteCode.generate(firstName: appModel.currentUser.name)
                        showingInvite = true
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
