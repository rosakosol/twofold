//
//  OnboardingTypes.swift
//  Twofold
//

import Foundation

enum OnboardingStep: Hashable {
    case createAccount
    case homeCity
    case relationshipContext
    case seeingFrequency
    case connectPartner
    case shareInvite
    case enterPartnerCode
    case joinInvite
    case connectedReveal
    case nextTrip
    case addTripDetails
    case reveal
}

enum OnboardingRole {
    case inviter
    case invitee
}

enum RelationshipStatus: String, CaseIterable, Identifiable {
    case livingApart = "Yes, we live apart"
    case temporarilyApart = "We're temporarily apart"
    case travelSeparately = "Not yet, but we travel separately often"

    var id: String { rawValue }
}

enum SeeingFrequency: String, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case everyFewWeeks = "Every few weeks"
    case monthly = "Monthly"
    case everyFewMonths = "Every few months"
    case itVaries = "It varies"

    var id: String { rawValue }
}

enum TripTraveler: String, CaseIterable, Identifiable {
    case you = "You"
    case partner = "Partner"
    case both = "Both"

    var id: String { rawValue }
}
