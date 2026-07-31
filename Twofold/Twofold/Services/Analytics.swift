//
//  Analytics.swift
//  Twofold
//
//  Thin capture wrapper + the app's single source of truth for event names, so the same event
//  fired from multiple call sites (e.g. `Event.inviteRedeem` — 4 different onboarding screens can
//  redeem a partner code) can't drift into slightly different strings. Naming follows PostHog's
//  own recommended convention: `category:object_action`, snake_case, present-tense verbs.
//  See `AnalyticsConfig` for SDK bring-up.
//

import Foundation
import PostHog

enum Analytics {
    enum Event {
        // Onboarding
        static let accountCreate = "onboarding:account_create"
        static let signIn = "onboarding:sign_in"
        static let passwordResetRequest = "onboarding:password_reset_request"
        static let inviteRedeem = "onboarding:invite_redeem"

        // Subscription
        static let paywallView = "subscription:paywall_view"
        static let purchaseComplete = "subscription:purchase_complete"
        static let restoreComplete = "subscription:restore_complete"

        // Flights & trips
        static let flightAdd = "flights:flight_add"
        static let flightDelete = "flights:flight_delete"
        static let tripCreate = "trips:trip_create"
        static let tripDelete = "trips:trip_delete"

        // Memories
        static let memoryCreate = "memories:memory_create"
        static let memoryDelete = "memories:memory_delete"

        // Games
        static let sessionStart = "games:session_start"
        static let sessionComplete = "games:session_complete"

        // Drawing pad
        static let doodleSave = "drawing_pad:doodle_save"

        // Partner
        static let partnerRemove = "partner:partner_remove"

        // Settings
        static let exportHistoryGenerated = "settings:export_history_generated"
    }

    static func capture(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    /// Onboarding's questionnaire answers (attribution/relationship situation/travel frequency/
    /// goals), set as durable PostHog *person* properties rather than a one-off event payload —
    /// these describe who the user is, not something that happened, so they belong on the
    /// profile itself (segmentable in PostHog's UI, present on every later event automatically)
    /// rather than needing to be re-derived from a single "account created" event every time.
    /// Called once, from `AppModel.applyOnboardingAccount`, at the one point a real user id
    /// exists and every answer has been collected — before this, `OnboardingModel`'s own answers
    /// were held in memory for the length of onboarding and then simply discarded.
    static func setOnboardingTraits(
        userID: UUID,
        attribution: AttributionSource?,
        situation: RelationshipSituation?,
        frequency: TravelFrequency?,
        goals: Set<OnboardingGoal>,
        userGender: Gender?,
        partnerGender: Gender?
    ) {
        var properties: [String: Any] = [:]
        if let attribution { properties["attribution_source"] = attribution.rawValue }
        if let situation { properties["relationship_situation"] = situation.rawValue }
        if let frequency { properties["travel_frequency"] = frequency.rawValue }
        if !goals.isEmpty { properties["onboarding_goals"] = goals.map(\.rawValue).sorted() }
        if let userGender { properties["gender"] = userGender.rawValue }
        if let partnerGender { properties["partner_gender"] = partnerGender.rawValue }
        guard !properties.isEmpty else { return }
        PostHogSDK.shared.identify(userID.uuidString, userProperties: properties)
    }
}
