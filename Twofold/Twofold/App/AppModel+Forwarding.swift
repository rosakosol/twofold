//
//  AppModel+Forwarding.swift
//  Twofold
//
//  The names state had when it lived on `AppModel`, reading through to the child store that holds
//  it now. They exist so the views and tests did not have to change in the same commit as the
//  move. New code can read the store directly (`appModel.subscription.tier`), and once nothing
//  uses a forwarder it can go.
//
//  Observation still works through them: each store is `@Observable`, so a view that reads
//  `appModel.subscriptionTier` is tracking `appModel.subscription.tier`.
//

import Foundation

// MARK: - SubscriptionState

extension AppModel {
    var isSubscriptionActive: Bool {
        get { subscription.isActive }
        set { subscription.isActive = newValue }
    }
    var viewerHoldsSubscription: Bool {
        get { subscription.viewerHoldsSubscription }
        set { subscription.viewerHoldsSubscription = newValue }
    }
    var subscriptionTier: String? {
        get { subscription.tier }
        set { subscription.tier = newValue }
    }

}

// MARK: - PromptsState

extension AppModel {
    var partnerDisconnectedMessage: String? {
        get { prompts.partnerDisconnectedMessage }
        set { prompts.partnerDisconnectedMessage = newValue }
    }
    var writeRefusedMessage: String? {
        get { prompts.writeRefusedMessage }
        set { prompts.writeRefusedMessage = newValue }
    }
    var partnerConnectedCelebrationShown: Bool {
        get { prompts.partnerConnectedCelebrationShown }
        set { prompts.partnerConnectedCelebrationShown = newValue }
    }
    var setupChecklistDismissed: Bool {
        get { prompts.setupChecklistDismissed }
        set { prompts.setupChecklistDismissed = newValue }
    }
    var partnerSubscriptionLapsedPartnerName: String? {
        get { prompts.partnerSubscriptionLapsedPartnerName }
        set { prompts.partnerSubscriptionLapsedPartnerName = newValue }
    }
    func markPartnerSubscriptionLapseAcknowledged() { prompts.markPartnerSubscriptionLapseAcknowledged() }
}

// MARK: - GamesState

extension AppModel {

    func refreshDailyStreak() async { await games.refreshDailyStreak() }
    func refreshGameDecks() async { await games.refreshGameDecks() }
    func decks(for topic: GameTopic) -> [GameDeck] { games.decks(for: topic) }
    func decks(ofType gameType: GameType) -> [GameDeck] { games.decks(ofType: gameType) }
}

// MARK: - TravelStore

extension AppModel {
    var trips: [Trip] {
        get { travel.trips }
        set { travel.trips = newValue }
    }
    var memories: [Memory] {
        get { travel.memories }
        set { travel.memories = newValue }
    }
    var flights: [Flight] {
        get { travel.flights }
        set { travel.flights = newValue }
    }

    func refreshFlights() async { await travel.refreshFlights() }
    func refreshMemories() async { await travel.refreshMemories() }
    func refreshTrips() async { await travel.refreshTrips() }
}

// MARK: - CoupleSession

extension AppModel {
    var hasCouple: Bool {
        get { session.hasCouple }
        set { session.hasCouple = newValue }
    }
    var needsOnboarding: Bool {
        get { session.needsOnboarding }
        set { session.needsOnboarding = newValue }
    }
    var hasSavedOnboardingProgress: Bool {
        get { session.hasSavedOnboardingProgress }
        set { session.hasSavedOnboardingProgress = newValue }
    }
    var couple: Couple {
        get { session.couple }
        set { session.couple = newValue }
    }
    var partnerConnected: Bool {
        get { session.partnerConnected }
        set { session.partnerConnected = newValue }
    }
    var inviteCode: String? {
        get { session.inviteCode }
        set { session.inviteCode = newValue }
    }
    var pendingConnectionRequests: [BackendService.PendingConnectionRequest] {
        get { session.pendingConnectionRequests }
        set { session.pendingConnectionRequests = newValue }
    }
    var pendingOutgoingConnectionRequest: BackendService.OutgoingConnectionRequest? {
        get { session.pendingOutgoingConnectionRequest }
        set { session.pendingOutgoingConnectionRequest = newValue }
    }
    var backendCoupleID: UUID? { session.backendCoupleID }

    func refreshPendingConnectionRequests() async { await session.refreshPendingConnectionRequests() }
    func refreshPendingOutgoingConnectionRequest() async { await session.refreshPendingOutgoingConnectionRequest() }
}
