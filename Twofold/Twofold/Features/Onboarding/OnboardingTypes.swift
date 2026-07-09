//
//  OnboardingTypes.swift
//  Twofold
//

import Foundation

enum OnboardingStep: Hashable {
    // Default "Get started" flow
    case situation
    case frequency
    case attribution
    case goals
    case yourName
    case partnerName
    case benchmark
    case coupleLocations
    case personalizedInsight
    case notificationsSell
    case liveActivitySell
    case widgetSell
    case addFirstFlight
    case twofoldPreview
    case trialTrust
    case paywall
    case purchaseSuccess
    case saveAccount

    // Preserved deep-link / manual-invite path
    case createAccount
    case homeCity
    case addPhoto
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

/// Which of the five relationship/travel situations most sounds like this couple —
/// drives the copy and conditional frequency options throughout the rest of onboarding.
/// "Live together but travel often" and "often take separate trips" used to be separate
/// cards but described the same thing, so they're merged into one.
enum RelationshipSituation: String, CaseIterable, Identifiable {
    case longDistance
    case liveTogetherTravelOften
    case temporarilyApart
    case haventMetYet
    case other

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .longDistance: "🌍"
        case .liveTogetherTravelOften: "🏠✈️"
        case .temporarilyApart: "📦"
        case .haventMetYet: "💌"
        case .other: "❤️"
        }
    }

    var title: String {
        switch self {
        case .longDistance: "We're long distance"
        case .liveTogetherTravelOften: "We live together, but one of us travels often"
        case .temporarilyApart: "We're temporarily apart"
        case .haventMetYet: "We haven't met yet"
        case .other: "Something else"
        }
    }

    var subtitle: String? {
        switch self {
        case .longDistance: "We live in different cities or countries"
        case .liveTogetherTravelOften: "Work trips and time apart from home"
        case .temporarilyApart: "The distance isn't forever"
        case .haventMetYet: "We're getting to know each other before meeting in person"
        case .other: nil
        }
    }
}

/// Flat set of every option shown across the three conditional frequency branches —
/// `FrequencyView` filters to the relevant subset based on `RelationshipSituation`, but a
/// single type keeps downstream copy (benchmark screen) simple to switch over.
enum TravelFrequency: String, CaseIterable, Identifiable {
    case everyFewWeeks = "Every few weeks"
    case every1to2Months = "Every 1–2 months"
    case every3to4Months = "Every 3–4 months"
    case aFewTimesAYear = "A few times a year"
    case everyFewMonths = "Every few months"
    case mostMonths = "Most months"
    case aFewTimesAMonth = "A few times a month"
    case almostEveryWeek = "Almost every week"
    case lessThanAMonth = "Less than a month"
    case oneToThreeMonths = "1–3 months"
    case threeToSixMonths = "3–6 months"
    case sixToTwelveMonths = "6–12 months"
    case notSureYet = "We're not sure yet"

    var id: String { rawValue }
}

enum AttributionSource: String, CaseIterable, Identifiable {
    case tiktok = "TikTok"
    case instagram = "Instagram"
    case reddit = "Reddit"
    case appStore = "App Store"
    case friendOrPartner = "A friend or partner"
    case google = "Google"
    case other = "Other"

    var id: String { rawValue }
}

/// What would make time apart feel easier — multi-select, stored as a `Set` so the app can
/// later personalise/reorder home-screen content based on which goals were picked.
enum OnboardingGoal: String, CaseIterable, Identifiable {
    case knowWhenLands
    case countdown
    case trackTrips
    case lookBack
    case localTime
    case feelCloser

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .knowWhenLands: "✈️"
        case .countdown: "⏳"
        case .trackTrips: "🗺️"
        case .lookBack: "🌍"
        case .localTime: "🕐"
        case .feelCloser: "❤️"
        }
    }

    var title: String {
        switch self {
        case .knowWhenLands: "Know when my partner lands"
        case .countdown: "Count down until we're together"
        case .trackTrips: "Keep track of our trips"
        case .lookBack: "Look back at where we've been"
        case .localTime: "Keep up with their local time"
        case .feelCloser: "Feel a little closer while we're apart"
        }
    }

    var subtitle: String? {
        switch self {
        case .knowWhenLands: "Get live updates when they're travelling"
        case .countdown: "Always know how long until you see each other"
        case .trackTrips: "Keep every journey together in one place"
        case .lookBack: "Build a history of your time together"
        case .localTime: "Know what time it is for them at a glance"
        case .feelCloser: nil
        }
    }
}

enum TripTraveler: String, CaseIterable, Identifiable {
    case you = "You"
    case partner = "Partner"
    case both = "Both"

    var id: String { rawValue }
}
