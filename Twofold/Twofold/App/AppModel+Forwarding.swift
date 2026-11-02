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
    var viewerSubscriptionStore: String? {
        get { subscription.viewerStore }
        set { subscription.viewerStore = newValue }
    }
    var hasResolvedSubscription: Bool { subscription.hasResolved }
    func markSubscriptionResolved() { subscription.markResolved() }
    var canAddContent: Bool { subscription.canAddContent }
    var isPremiumLocked: Bool { subscription.isPremiumLocked }
    func isDeckLocked(_ deck: GameDeck) -> Bool { subscription.isDeckLocked(deck) }

    static func isSubscribed(backendSaysActive: Bool, deviceTier: SubscriptionTier?) -> Bool {
        SubscriptionState.isSubscribed(backendSaysActive: backendSaysActive, deviceTier: deviceTier)
    }
    static func deviceTier() async -> SubscriptionTier? {
        await SubscriptionState.deviceTier()
    }
    static func isWebManagedStore(_ store: String?) -> Bool {
        SubscriptionState.isWebManagedStore(store)
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
    var pendingReviewMilestone: ReviewMilestone? {
        get { prompts.pendingReviewMilestone }
        set { prompts.pendingReviewMilestone = newValue }
    }
    var pendingPartnerInviteNudge: Bool {
        get { prompts.pendingPartnerInviteNudge }
        set { prompts.pendingPartnerInviteNudge = newValue }
    }
    func markPartnerConnectedCelebrationShown() { prompts.markPartnerConnectedCelebrationShown() }
    func markPartnerSubscriptionLapseAcknowledged() { prompts.markPartnerSubscriptionLapseAcknowledged() }
    func dismissSetupChecklist() { prompts.dismissSetupChecklist() }
    func noteReviewMilestone(_ milestone: ReviewMilestone) { prompts.noteReviewMilestone(milestone) }
}

// MARK: - GamesState

extension AppModel {
    var dailyStreak: Int? {
        get { games.dailyStreak }
        set { games.dailyStreak = newValue }
    }
    var longestDailyStreak: Int? {
        get { games.longestDailyStreak }
        set { games.longestDailyStreak = newValue }
    }
    var dailyStreakResetsAt: Date? {
        get { games.dailyStreakResetsAt }
        set { games.dailyStreakResetsAt = newValue }
    }
    var streakRepair: BackendService.StreakRepairState? {
        get { games.streakRepair }
        set { games.streakRepair = newValue }
    }
    var todaysDailySessionID: UUID? {
        get { games.todaysDailySessionID }
        set { games.todaysDailySessionID = newValue }
    }
    var todaysDailyQuestionText: String? {
        get { games.todaysDailyQuestionText }
        set { games.todaysDailyQuestionText = newValue }
    }
    var isLoadingDailyQuestion: Bool { games.isLoadingDailyQuestion }
    var todaysMyAnswered: Bool {
        get { games.todaysMyAnswered }
        set { games.todaysMyAnswered = newValue }
    }
    var todaysPartnerAnswered: Bool {
        get { games.todaysPartnerAnswered }
        set { games.todaysPartnerAnswered = newValue }
    }
    var dailyQuestionError: String? {
        get { games.dailyQuestionError }
        set { games.dailyQuestionError = newValue }
    }
    var gameDecks: [GameDeck]? { games.gameDecks }
    var gameDecksUnavailable: Bool { games.gameDecksUnavailable }
    var deckProgress: [UUID: DeckProgress]? { games.deckProgress }
    var adultContentStatus: BackendService.AdultContentStatus? { games.adultContentStatus }
    var isDailyQuestionOpenRequested: Bool {
        get { games.isDailyQuestionOpenRequested }
        set { games.isDailyQuestionOpenRequested = newValue }
    }

    func startOrResumeDailyQuestion() async { await games.startOrResumeDailyQuestion() }
    func refreshStreakRepairState() async { await games.refreshStreakRepairState() }
    func refreshDailyStreak() async { await games.refreshDailyStreak() }
    func recordGameStateForOffline() { games.recordGameStateForOffline() }
    func loadGameDecksIfNeeded() async { await games.loadGameDecksIfNeeded() }
    func refreshGameDecks() async { await games.refreshGameDecks() }
    func refreshAdultContentStatus() async { await games.refreshAdultContentStatus() }
    func setAdultContentOptIn(_ isOn: Bool) async throws { try await games.setAdultContentOptIn(isOn) }
    func markDeckProgressMineCompleted(deckID: UUID?) { games.markDeckProgressMineCompleted(deckID: deckID) }
    func decks(for topic: GameTopic) -> [GameDeck] { games.decks(for: topic) }
    func decks(ofType gameType: GameType) -> [GameDeck] { games.decks(ofType: gameType) }
    func topicProgress(_ topic: GameTopic) -> (played: Int, total: Int)? { games.topicProgress(topic) }
}
