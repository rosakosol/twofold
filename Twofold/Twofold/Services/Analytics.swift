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
}
