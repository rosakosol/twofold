//
//  AddFlightFlowModel.swift
//  Twofold
//
//  Shared step state for AddFlightFlowView, injected via .environment instead of threading
//  bindings through every step screen.
//

import CoreLocation
import Foundation

enum AirportRole: Hashable {
    case departure
    case destination
}

enum AddFlightFlowStep: Hashable {
    case flightNumber
    case airlinePicker
    case airport(AirportRole)
    case date
    case results
}

@Observable
final class AddFlightFlowModel {
    enum Mode {
        case flightNumber
        case route
    }

    var path: [AddFlightFlowStep] = []
    var mode: Mode = .flightNumber

    // Flight-number path
    var airlineEntry: AirlineEntry?

    /// Digits only, enforced here rather than trusted from each writer.
    ///
    /// Every other path into this already filtered — `AddFlightEntryStepView` uses
    /// `query.filter(\.isNumber)` in three places and this model's own init does the same. The one
    /// place a person actually types, `FlightNumberStepView`'s field, bound straight to it. That
    /// field is `.numberPad`, which shapes the on-screen keyboard and stops nothing else: a paste,
    /// a hardware keyboard or dictation all put letters in.
    ///
    /// What that cost: the search sends `airline.iata + digits`, so pasting "QF123" produced
    /// "QFQF123" — a malformed ident, a billed AeroAPI request, and "no flights found" for a
    /// flight that exists.
    var flightNumberDigits: String = "" {
        didSet {
            let digitsOnly = flightNumberDigits.filter(\.isNumber)
            if digitsOnly != flightNumberDigits { flightNumberDigits = digitsOnly }
        }
    }

    // Route path
    var departureAirport: Airport?
    var destinationAirport: Airport?

    var date: Date = .now

    var candidates: [AeroFlightCandidate] = []
    var isSearching = false
    var searchError: String?

    /// Ranking signal for airport suggestions — typically the caller's already-collected home
    /// city. No new location-permission flow is introduced for this; when nil, airport search
    /// just falls back to relevance-only ordering.
    let nearCoordinate: CLLocationCoordinate2D?

    /// Present on every step's top bar — "Cancel" for the live app, "Add this later" for
    /// onboarding.
    let topBarTitle: String
    let onTopBarAction: () -> Void

    /// Set when this flow was opened from a specific trip's "Link a flight" screen's "Create
    /// new" option — preselects `FlightConfirmationView`'s own "Link to a trip" picker to this
    /// trip, rather than the caller having to remember to pick it again after searching.
    let initialTripID: Trip.ID?

    init(
        nearCoordinate: CLLocationCoordinate2D?,
        topBarTitle: String,
        onTopBarAction: @escaping () -> Void,
        initialFlightNumberDigits: String? = nil,
        initialTripID: Trip.ID? = nil
    ) {
        self.nearCoordinate = nearCoordinate
        self.topBarTitle = topBarTitle
        self.onTopBarAction = onTopBarAction
        self.initialTripID = initialTripID
        // `flightNumberDigits` filters on write now, so this could pass the raw value — kept
        // explicit because the emptiness check below has to test the filtered result, not the input.
        let digitsOnly = (initialFlightNumberDigits ?? "").filter(\.isNumber)
        if !digitsOnly.isEmpty {
            mode = .flightNumber
            flightNumberDigits = digitsOnly
            path = [.flightNumber]
        }
    }
}
