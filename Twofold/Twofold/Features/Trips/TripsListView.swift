//
//  TripsListView.swift
//  Twofold
//

import SwiftUI

struct TripsListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var filter: TripFilter = .all

    enum TripFilter: String, CaseIterable {
        case all = "All"
        case seeingEachOther = "To see each other"
        case together = "Together"
        case personal = "Personal"

        var category: TripCategory? {
            switch self {
            case .all: nil
            case .seeingEachOther: .seeingEachOther
            case .together: .together
            case .personal: .personal
            }
        }
    }

    private func traveler(for trip: Trip) -> Person {
        appModel.couple.partner(trip.travelerID) ?? appModel.currentUser
    }

    private func filtered(_ trips: [Trip]) -> [Trip] {
        guard let category = filter.category else { return trips }
        return trips.filter { $0.category == category }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(TripFilter.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, Theme.Spacing.sm)
                }

                let upcoming = filtered(appModel.upcomingTrips)
                if !upcoming.isEmpty {
                    Section("Upcoming") {
                        ForEach(upcoming) { trip in
                            if trip.isActive {
                                NavigationLink {
                                    FlightTrackingView(trip: trip)
                                } label: {
                                    TripRowView(trip: trip, traveler: traveler(for: trip))
                                }
                            } else {
                                TripRowView(trip: trip, traveler: traveler(for: trip))
                            }
                        }
                    }
                }

                let past = filtered(appModel.pastTrips)
                if !past.isEmpty {
                    Section("Past") {
                        ForEach(past) { trip in
                            TripRowView(trip: trip, traveler: traveler(for: trip))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Trips")
        }
    }
}

#Preview {
    TripsListView()
        .environment(AppModel())
}
