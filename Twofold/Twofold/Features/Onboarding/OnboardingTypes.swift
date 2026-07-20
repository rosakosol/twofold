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
    case gender
    case coupleLocations
    case anniversaryDate
    case happyAnniversary
    case personalizedInsight
    case notificationsSell
    case liveActivitySell
    case memoriesSell
    case mapSell
    case firstMemoryIntro
    case firstMemory
    case twofoldPreview
    case saveAccount
    case invitePartner
    case trialTrust
    case paywall
    case purchaseSuccess

    // Preserved deep-link / manual-invite path
    case createAccount
    case homeCity
    case addPhoto
    case connectPartner
    case shareInvite
    case enterPartnerCode
    case joinInvite
    case connectionRequestSent
    case nextTrip
    case addTripDetails
    case reveal

    /// PostHog `$screen_name` for this step — tagged once at `OnboardingCoordinatorView`'s single
    /// `.navigationDestination` choke point rather than on each of the 31 individual screens.
    var analyticsName: String {
        switch self {
        case .situation: "Onboarding: Situation"
        case .frequency: "Onboarding: Frequency"
        case .attribution: "Onboarding: Attribution"
        case .goals: "Onboarding: Goals"
        case .yourName: "Onboarding: Your Name"
        case .partnerName: "Onboarding: Partner Name"
        case .gender: "Onboarding: Gender"
        case .coupleLocations: "Onboarding: Couple Locations"
        case .anniversaryDate: "Onboarding: Anniversary Date"
        case .happyAnniversary: "Onboarding: Happy Anniversary"
        case .personalizedInsight: "Onboarding: Personalized Insight"
        case .notificationsSell: "Onboarding: Notifications Sell"
        case .liveActivitySell: "Onboarding: Live Activity Sell"
        case .memoriesSell: "Onboarding: Memories Sell"
        case .mapSell: "Onboarding: Map Sell"
        case .firstMemoryIntro: "Onboarding: First Memory Intro"
        case .firstMemory: "Onboarding: First Memory"
        case .twofoldPreview: "Onboarding: Twofold Preview"
        case .saveAccount: "Onboarding: Save Account"
        case .invitePartner: "Onboarding: Invite Partner"
        case .trialTrust: "Onboarding: Trial Trust"
        case .paywall: "Onboarding: Paywall"
        case .purchaseSuccess: "Onboarding: Purchase Success"
        case .createAccount: "Onboarding: Create Account"
        case .homeCity: "Onboarding: Home City"
        case .addPhoto: "Onboarding: Add Photo"
        case .connectPartner: "Onboarding: Connect Partner"
        case .shareInvite: "Onboarding: Share Invite"
        case .enterPartnerCode: "Onboarding: Enter Partner Code"
        case .joinInvite: "Onboarding: Join Invite"
        case .connectionRequestSent: "Onboarding: Connection Request Sent"
        case .nextTrip: "Onboarding: Next Trip"
        case .addTripDetails: "Onboarding: Add Trip Details"
        case .reveal: "Onboarding: Reveal"
        }
    }
}

enum OnboardingRole {
    case inviter
    case invitee
}

/// Drives which possessive pronoun ("his"/"her"/) copy uses when referring to
/// someone by name elsewhere in onboarding, instead of the generic "their".
enum Gender: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }

    var title: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        }
    }

    var emoji: String {
        switch self {
        case .male: "♂️"
        case .female: "♀️"
        }
    }

    var possessive: String {
        switch self {
        case .male: "his"
        case .female: "her"
        }
    }
}

/// Which of the five relationship/travel situations most sounds like this couple —
/// drives the copy and conditional frequency options throughout the rest of onboarding.
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
        case .liveTogetherTravelOften: "✈️"
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
        case .haventMetYet: "We're counting down to our first meeting in person"
        case .other: nil
        }
    }
}

/// Flat set of every option shown across the three conditional frequency branches —
/// `FrequencyView` filters to the relevant subset based on `RelationshipSituation`, but a
/// single type keeps downstream copy simple to switch over.
enum TravelFrequency: String, CaseIterable, Identifiable {
    case everyFewWeeks = "Every few weeks"
    case every1to2Months = "Every 1-2 months"
    case every3to4Months = "Every 3-4 months"
    case aFewTimesAYear = "A few times a year"
    case everyFewMonths = "Every few months"
    case mostMonths = "Most months"
    case aFewTimesAMonth = "A few times a month"
    case almostEveryWeek = "Almost every week"
    case lessThanAMonth = "Less than a month"
    case oneToThreeMonths = "1-3 months"
    case threeToSixMonths = "3-6 months"
    case sixToTwelveMonths = "6-12 months"
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
    case feelCloser

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .knowWhenLands: "✈️"
        case .countdown: "⏳"
        case .trackTrips: "🗺️"
        case .lookBack: "🌍"
        case .feelCloser: "❤️"
        }
    }

    var title: String {
        switch self {
        case .knowWhenLands: "Know when my partner travels"
        case .countdown: "Count down until we're together"
        case .trackTrips: "Keep track of our trips"
        case .lookBack: "Relive our memories"
        case .feelCloser: "Feel closer while we're apart"
        }
    }

    var subtitle: String? {
        switch self {
        case .knowWhenLands:
            return "Get live flight updates and arrival notifications"
        case .countdown:
            return "Always know when you'll see each other next"
        case .trackTrips:
            return "Keep every journey together in one place"
        case .lookBack:
            return "Revisit the places and moments you've shared"
        case .feelCloser:
            return "Keep your connection strong with fun couple games"
        }
    }
}

enum TripTraveler: String, CaseIterable, Identifiable {
    case you = "You"
    case partner = "Partner"
    case both = "Both"

    var id: String { rawValue }
}
