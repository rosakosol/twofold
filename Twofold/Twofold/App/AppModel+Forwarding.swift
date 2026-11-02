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
    var activeTrip: Trip? { travel.activeTrip }
    var activeOrUpcomingFlights: [Flight] { travel.activeOrUpcomingFlights }
    var activeOrUpcomingFlight: Flight? { travel.activeOrUpcomingFlight }
    var upcomingTrips: [Trip] { travel.upcomingTrips }
    var pastTrips: [Trip] { travel.pastTrips }
    var completedFlights: [Flight] { travel.completedFlights }
    var nextReunionTripID: Trip.ID? { travel.nextReunionTripID }
    var nextReunionDaysToGo: Int { travel.nextReunionDaysToGo }
    func memories(in place: Place) -> [Memory] { travel.memories(in: place) }
    var citiesWithMemories: [Place] { travel.citiesWithMemories }
    func travellerIDs(for flight: Flight) -> [UUID] { travel.travellerIDs(for: flight) }

    @discardableResult
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, category: TripCategory, flightCandidates: [AeroFlightCandidate] = []) async -> Trip {
        await travel.addTrip(origin: origin, destination: destination, departureDate: departureDate, arrivalDate: arrivalDate, traveler: traveler, category: category, flightCandidates: flightCandidates)
    }
    func refreshFlights() async { await travel.refreshFlights() }
    func resolveMissingAirportTimezones() async { await travel.resolveMissingAirportTimezones() }
    func refreshMemories() async { await travel.refreshMemories() }
    func refreshTrips() async { await travel.refreshTrips() }
    func deleteFlight(_ flight: Flight) async { await travel.deleteFlight(flight) }
    func deleteFlights(_ flights: [Flight]) async { await travel.deleteFlights(flights) }
    func updateTripNotes(_ trip: Trip) async { await travel.updateTripNotes(trip) }
    func updateTrip(_ trip: Trip, from base: Trip? = nil) async { await travel.updateTrip(trip, from: base) }
    func deleteTrip(_ trip: Trip) async { await travel.deleteTrip(trip) }
    func deleteTrips(_ trips: [Trip]) async { await travel.deleteTrips(trips) }
    func linkFlight(_ flight: Flight, to trip: Trip) async { await travel.linkFlight(flight, to: trip) }
    func unlinkFlight(_ flight: Flight) async { await travel.unlinkFlight(flight) }
    func setFlightTravelers(_ flight: Flight, travelerIDs: [UUID]) async { await travel.setFlightTravelers(flight, travelerIDs: travelerIDs) }
    func linkMemory(_ memory: Memory, to trip: Trip) async { await travel.linkMemory(memory, to: trip) }
    func unlinkMemory(_ memory: Memory) async { await travel.unlinkMemory(memory) }

    @discardableResult
    func addMemory(title: String, place: Place?, date: Date, note: String, imagesData: [Data]) async -> Memory {
        await travel.addMemory(title: title, place: place, date: date, note: note, imagesData: imagesData)
    }
    func updateMemory(_ memory: Memory, from base: Memory? = nil, newImagesData: [Data] = []) async {
        await travel.updateMemory(memory, from: base, newImagesData: newImagesData)
    }
    func removePhoto(_ photo: MemoryPhoto, from memory: Memory) async { await travel.removePhoto(photo, from: memory) }
    func deleteMemory(_ memory: Memory) async { await travel.deleteMemory(memory) }
    func deleteMemories(_ memories: [Memory]) async { await travel.deleteMemories(memories) }
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
    var hasResolvedOutgoingConnectionRequest: Bool { session.hasResolvedOutgoingConnectionRequest }
    var hasLoadedCoupleState: Bool { session.hasLoadedCoupleState }
    var backendCoupleID: UUID? { session.backendCoupleID }

    func refreshPendingConnectionRequests() async { await session.refreshPendingConnectionRequests() }
    func refreshPendingOutgoingConnectionRequest() async { await session.refreshPendingOutgoingConnectionRequest() }
    @discardableResult
    func sendConnectionRequestReminder() async -> String? { await session.sendConnectionRequestReminder() }
}
