//
//  AppModel.swift
//  Twofold
//
//  Root store backed by Supabase. `couple`/`trips`/`memories` are loaded from the backend
//  once a session exists.
//

import Foundation
import Observation
import PostHog
import RevenueCat

@Observable
final class AppModel {
    var isLoadingSession = true
    var hasCouple: Bool = false
    var couple: Couple = AppModel.placeholderCouple
    var trips: [Trip] = []
    var memories: [Memory] = []
    /// Every flight for the couple, independent of trip linkage — the authoritative list.
    /// See `Trip.flight` for the trip-scoped mirror kept for backward-compat UI.
    var flights: [Flight] = []
    /// Home-screen doodle pads — only meaningful once paired, since there's no partner pad to
    /// compare against (and nowhere real to save to) before then.
    var myDrawingURL: URL?
    var partnerDrawingURL: URL?

    /// "Your partner doesn't pay anything" — true if *either* partner's device last reported
    /// an active local StoreKit entitlement (see `BackendService.fetchSubscriptionActive`).
    /// `RootView` gates all of `MainTabView` behind this once `hasCouple` is true.
    var isSubscriptionActive = false
    /// "plus"/"premium", the higher of the two partners' tiers — nil for pre-existing
    /// subscribers from before this column existed (`start_game_session` treats that the same
    /// as "plus" server-side, so this being nil never actually locks anyone out of content).
    var subscriptionTier: String?

    /// Daily Activity streak — see `startOrResumeDailyQuestion()`/`refreshDailyStreak()`. Nil
    /// until the first fetch resolves (not defaulted to 0) so `DailyActivityCard` can show a
    /// placeholder instead of visibly flashing "Start a streak" before the real value loads.
    var dailyStreak: Int?
    var longestDailyStreak: Int?
    /// Today's Daily Activity session id, once known (fetched lazily, not at launch — see
    /// `startOrResumeDailyQuestion()`).
    var todaysDailySessionID: UUID?
    /// The actual discussion topic text for today's session — shown on `DailyActivityCard`
    /// instead of a generic teaser line. Nil while loading or if the fetch fails.
    var todaysDailyQuestionText: String?

    /// All active decks + which ones this couple has started, cached after first load
    /// (`loadGameDecksIfNeeded()`) — powers the Games hub's topic list and progress bars. Not
    /// loaded at app launch; only Games-hub visits need it.
    private(set) var gameDecks: [GameDeck]?
    /// Per-deck completion counts for the couple — see `DeckProgress`/`get_deck_progress()`.
    /// Superseded `playedDeckIDs` (a deck has progress here the moment either partner starts it).
    private(set) var deckProgress: [UUID: DeckProgress]?

    /// Whether the partner has actually redeemed an invite and joined — confirmed by the
    /// backend (an active `couples` row exists), not assumed the moment a code is shared.
    var partnerConnected: Bool = false
    var inviteCode: String?

    /// Set whenever a newly-crossed, not-yet-shown review milestone is detected — RootView
    /// presents `ReviewPromptView` as a sheet whenever this is non-nil. See
    /// `checkReviewMilestones()`/`noteReviewMilestone(_:)`.
    var pendingReviewMilestone: ReviewMilestone?

    /// Set once a real `couples` row exists for this user.
    private var backendCoupleID: UUID?
    /// Trips/memories added locally before pairing completed (no couple to attach them to
    /// yet). Flushed to the backend the moment a real couple shows up.
    private var pendingTripIDs: Set<Trip.ID> = []
    private var pendingMemoryIDs: Set<Memory.ID> = []
    /// A pending memory's photos can't be uploaded until there's a real couple to namespace the
    /// storage path under — held here so they aren't silently dropped, and uploaded once paired.
    private var pendingMemoryPhotoData: [Memory.ID: [Data]] = [:]

    var currentUser: Person { couple.partnerA }
    var partner: Person { couple.partnerB }

    var needsPartnerInvite: Bool { !partnerConnected }
    var needsFirstTrip: Bool { trips.isEmpty }
    var needsFirstFlight: Bool { !trips.contains { $0.flight != nil } }
    var needsHomeCities: Bool { couple.partnerA.homeCity == nil || couple.partnerB.homeCity == nil }

    var activeTrip: Trip? {
        trips.first { $0.isActive }
    }

    /// The couple's relevant tracked flights for the Home carousel — whichever are currently in
    /// progress or haven't departed yet, soonest departure first. Cancelled flights are excluded
    /// (nothing useful to show live for those).
    var activeOrUpcomingFlights: [Flight] {
        let relevant = flights.filter { !$0.cancelled && ($0.status.isActivelyTracked || ($0.bestArrival ?? .distantPast) > .now) }
        return relevant.sorted { ($0.bestDeparture ?? .distantFuture) < ($1.bestDeparture ?? .distantFuture) }
    }

    /// Convenience for call sites that only ever cared about the single most relevant flight.
    var activeOrUpcomingFlight: Flight? { activeOrUpcomingFlights.first }

    var upcomingTrips: [Trip] {
        trips.filter { $0.isUpcoming || $0.isActive }.sorted { $0.departureDate < $1.departureDate }
    }

    var pastTrips: [Trip] {
        trips.filter { !$0.isUpcoming && !$0.isActive }.sorted { $0.departureDate > $1.departureDate }
    }

    var stats: MockData.RelationshipStats {
        let totalDistance = trips.reduce(0) { $0 + $1.distanceKm }
        let daysTogether = max(0, Calendar.current.dateComponents([.day], from: couple.startedDatingOn, to: .now).day ?? 0)
        return MockData.RelationshipStats(
            totalDistanceKm: totalDistance,
            tripCount: trips.count,
            flightCount: trips.filter { $0.flight != nil }.count,
            countryCount: Set(trips.flatMap { [$0.origin.country, $0.destination.country] }).count,
            daysTogether: daysTogether,
            earthMultiple: totalDistance / Geo.earthCircumferenceKm
        )
    }

    var nextReunionDaysToGo: Int {
        guard let trip = upcomingTrips.first else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.departureDate).day ?? 0
        return max(0, days)
    }

    func memories(in place: Place) -> [Memory] {
        memories.filter { $0.place?.id == place.id }
    }

    var citiesWithMemories: [Place] {
        var seen = Set<UUID>()
        return memories.compactMap { memory in
            guard let place = memory.place, !seen.contains(place.id) else { return nil }
            seen.insert(place.id)
            return place
        }
    }

    // MARK: - Session / backend sync

    /// Called once at launch. Restores a session if one exists and loads real state; leaves
    /// `hasCouple = false` only when there's genuinely no session, so `RootView` routes into
    /// onboarding for a first-time user but never for a returning one who just hasn't paired
    /// with a partner yet (see `loadSignedInState`).
    func restoreSession() async {
        defer { isLoadingSession = false }
        guard await BackendService.restoreSession() != nil else { return }
        await loadSignedInState()
    }

    /// Called any time we know a Supabase session exists — at launch (`restoreSession`), right
    /// after a manual sign-in (`SignInView`), or after `removePartner()` dissolves a couple.
    /// Being authenticated at all means onboarding is already done, regardless of whether a
    /// `couples` row exists yet — so this always ends with `hasCouple = true`, rather than
    /// leaving a solo (unpaired) user to fall back into onboarding just because
    /// `fetchCoupleState` found nothing.
    func loadSignedInState() async {
        await identifyWithRevenueCat()
        identifyWithPostHog()
        restorePendingMemoriesFromDisk()
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
        } else if let profile = try? await BackendService.fetchOwnProfile() {
            await adoptSoloProfile(profile)
        }
        hasCouple = true
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        checkReviewMilestones()
    }

    /// Restores memories that were added before pairing (or otherwise never synced) from local
    /// disk — see `PendingMemoryStore`. Runs before `adopt(_:)`/`adoptSoloProfile(_:)` so
    /// whichever one runs next already sees them: `adopt(_:)` will attempt to sync them
    /// immediately (they're now in `pendingMemoryIDs`), and `adoptSoloProfile(_:)` preserves
    /// pending memories through its reset rather than discarding them. Skips anything already
    /// present (e.g. a second call this session) to avoid duplicate entries.
    private func restorePendingMemoriesFromDisk() {
        for (memory, photosData) in PendingMemoryStore.loadAll() {
            guard !memories.contains(where: { $0.id == memory.id }) else { continue }
            memories.append(memory)
            pendingMemoryIDs.insert(memory.id)
            if !photosData.isEmpty { pendingMemoryPhotoData[memory.id] = photosData }
        }
    }

    /// Resets to the solo (unpaired) state and repopulates from the caller's own profile —
    /// shared by `loadSignedInState()` (launch/sign-in) and `refreshCoupleStateIfNeeded()`
    /// (an already-connected device discovering the couple was dissolved elsewhere). Reset
    /// first: at launch these are already at their zero-value defaults so it's a no-op, but
    /// reused mid-session this clears the *old* partner's data (partnerConnected,
    /// backendCoupleID, trips/memories/flights, drawing pad URLs) that would otherwise survive
    /// and make a just-dissolved couple still look "connected" in the UI. Memories still in
    /// `pendingMemoryIDs` are the exception — they were never tied to any couple in the first
    /// place (added before ever pairing, still only durable via `PendingMemoryStore`), so they
    /// survive this reset rather than being discarded along with the dissolved couple's data.
    private func adoptSoloProfile(_ profile: BackendService.OwnProfileState) async {
        partnerConnected = false
        backendCoupleID = nil
        trips = []
        memories = memories.filter { pendingMemoryIDs.contains($0.id) }
        flights = []
        myDrawingURL = nil
        partnerDrawingURL = nil
        couple = Self.placeholderCouple

        couple.partnerA = profile.person
        if let partnerName = profile.partnerName, !partnerName.isEmpty {
            couple.partnerB.name = partnerName
        }
        if let partnerHomeCity = profile.partnerHomeCity {
            couple.partnerB.homeCity = partnerHomeCity
        }
        if let partnerAvatarURL = profile.partnerAvatarURL {
            couple.partnerB.avatarURL = partnerAvatarURL
        }
        if let anniversaryDate = profile.anniversaryDate {
            couple.startedDatingOn = anniversaryDate
        }
        isSubscriptionActive = profile.subscriptionActive
        subscriptionTier = profile.subscriptionTier
    }

    /// A device's own successful purchase/restore, applied instantly and locally (no network
    /// round-trip) — `PaywallView` calls this right after a purchase/restore succeeds, before
    /// its own `onSubscribed()` callback fires, so `RootView`'s gate never flashes a second
    /// paywall for someone who just subscribed (the Supabase write happens alongside this, but
    /// this local flag is what `RootView` actually reads).
    func markSubscriptionActive() {
        isSubscriptionActive = true
    }

    /// Tells RevenueCat who this device's user actually is, so its entitlement/purchase history
    /// is attributed to the same identity across every device that signs into this account —
    /// without this, RevenueCat would only ever see its own locally-generated anonymous ID,
    /// which a reinstall or a second device would never line up with. `Purchases.configure`
    /// (see `RevenueCatConfig`) runs before any Supabase session is known, so this is the
    /// earliest point that identity is actually available — called from `loadSignedInState()`
    /// itself rather than deeper in `adopt`/`adoptSoloProfile` since both of those paths need it
    /// equally and neither should have to remember to call it separately.
    private func identifyWithRevenueCat() async {
        guard let userID = BackendService.currentUserID else { return }
        _ = try? await Purchases.shared.logIn(userID.uuidString)
    }

    /// Same idea as `identifyWithRevenueCat()`, for PostHog — ties analytics events to the same
    /// stable Supabase user id instead of PostHog's own throwaway anonymous id, so a signed-in
    /// user's activity lines up across devices/reinstalls. Synchronous (unlike the RevenueCat
    /// call): `PostHogSDK.identify(_:)` just queues locally, no network round-trip to await.
    private func identifyWithPostHog() {
        guard let userID = BackendService.currentUserID else { return }
        PostHogSDK.shared.identify(userID.uuidString)
    }

    /// Signs out and resets all local state back to the pre-auth placeholder — `RootView`
    /// picks this up via `hasCouple` and routes back to `WelcomeView`.
    func signOut() async {
        try? await BackendService.signOut()
        _ = try? await Purchases.shared.logOut()
        PostHogSDK.shared.reset()
        hasCouple = false
        partnerConnected = false
        inviteCode = nil
        backendCoupleID = nil
        isSubscriptionActive = false
        pendingTripIDs = []
        pendingMemoryIDs = []
        pendingMemoryPhotoData = [:]
        trips = []
        memories = []
        flights = []
        couple = Self.placeholderCouple
    }

    private static var placeholderCouple: Couple {
        Couple(
            partnerA: Person(name: "You", accentColor: Person.palette[1]),
            partnerB: Person(name: "Partner", accentColor: Person.palette[0]),
            startedDatingOn: .now
        )
    }

    /// Persists profile edits from `SettingsView`. Each field only round-trips to the backend
    /// if it actually changed, since `updateFirstName`/`updateHomeCity` are separate writes.
    func updateProfile(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != couple.partnerA.name {
            try? await BackendService.updateFirstName(trimmedName)
            couple.partnerA.name = trimmedName
        }
    }

    func updateAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadAvatar(imageData: imageData)
        couple.partnerA.avatarURL = url
    }

    /// Always editable, paired or not — this is *your own, personal* name for your partner
    /// (a nickname, a pet name, whatever you call them), never their real account data. Your
    /// partner has their own independent nickname for you, if they've set one; neither side
    /// overwrites the other's. See `BackendService.updatePartnerNickname`.
    func updatePartnerName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != couple.partnerB.name else { return }
        try? await BackendService.updatePartnerNickname(trimmed)
        couple.partnerB.name = trimmed
    }

    /// Unlike the name (always personal), the city is shared/real once paired — only
    /// meaningful to set here before that, as a personalization guess. `SettingsView` disables
    /// this field once `partnerConnected` is true.
    func updatePartnerHomeCity(_ city: Place) async {
        guard city.id != couple.partnerB.homeCity?.id else { return }
        try? await BackendService.updatePartnerHomeCityGuess(city)
        couple.partnerB.homeCity = city
    }

    /// Always personal, paired or not — it's always *your own* custom photo of your partner,
    /// independent of whatever avatar they picked for themselves (see
    /// `BackendService.uploadPartnerAvatar`).
    func updatePartnerAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadPartnerAvatar(imageData: imageData)
        couple.partnerB.avatarURL = url
    }

    func updateAnniversaryDate(_ date: Date) async {
        guard date != couple.startedDatingOn else { return }
        try? await BackendService.updateAnniversaryDate(date)
        couple.startedDatingOn = date
    }

    /// Ends the current partnership. The couple row is dissolved, not deleted — every trip,
    /// memory, flight, and game session shared with them stays intact and stays readable later
    /// (only visible via Settings' "Archived data" screen, and only ever deleted for good if the
    /// user explicitly asks). Reloads signed-in state afterward, which naturally falls back to
    /// the same solo/not-yet-paired shape a brand-new user starts in — reuses
    /// `loadSignedInState()`'s existing "no active couple" branch rather than duplicating that
    /// reset logic here. Returns nil on success, or a message describing what went wrong — the
    /// underlying RPC's own rejection (e.g. "This couple has already been dissolved") is
    /// relayed rather than swallowed, since a generic error here gives no way to tell a real
    /// failure apart from a harmless double-tap/retry.
    func removePartner() async -> String? {
        guard let backendCoupleID else { return "No partner to remove." }
        do {
            try await BackendService.leaveCouple(coupleID: backendCoupleID)
        } catch {
            return error.localizedDescription
        }
        Analytics.capture(Analytics.Event.partnerRemove)
        await loadSignedInState()
        // HomeView's setup checklist card (the "invite your partner" hint) remembers a past
        // dismissal forever via this UserDefaults key — without clearing it, someone who'd
        // already dismissed it once (e.g. during their original onboarding) would see no hint
        // at all here, even though they're now genuinely back in the same unpaired state a
        // brand-new user starts in and need that same nudge again.
        UserDefaults.standard.set(false, forKey: "setupChecklistDismissed")
        return nil
    }

    /// Re-checks backend couple state without touching `isLoadingSession` — picks up a
    /// partner's invite redemption that happened while this device was backgrounded, the
    /// same idea as `GlobeHomeView`'s existing pending-share foreground refresh.
    /// Called on Home appearing/foregrounding — the name says "if needed" but it always
    /// re-checks now, in both directions: picks up a partner who just joined, *and* notices if
    /// an already-connected couple was dissolved elsewhere (another device, or directly) since
    /// this device last checked. Skipping the re-check whenever `partnerConnected` was already
    /// true used to mean a device could keep showing "connected" indefinitely after the couple
    /// was actually dissolved, until a full sign-out/sign-in or cold relaunch.
    func refreshCoupleStateIfNeeded() async {
        guard hasCouple else { return }
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
        } else if partnerConnected, let profile = try? await BackendService.fetchOwnProfile() {
            await adoptSoloProfile(profile)
        }
    }

    /// Drawing pad paths are fully deterministic (`{coupleID}/{personID}/pad.png`), so unlike
    /// trips/memories there's nothing to "fetch" beyond just pointing at the URL — this just
    /// primes both URLs so the pad previews have something to render on first appearance.
    ///
    /// Cache-busted on every call, not just right after a save — this runs from
    /// `DrawingPadCard.onAppear`, which SwiftUI re-fires when the drawing editor's sheet
    /// dismisses back to Home. Without busting here too, that re-fire was overwriting the
    /// fresh cache-busted URL `saveMyDrawing` had just set with a bare, non-busted one — so
    /// `AsyncImage` resolved it against a stale cached response and the new drawing only ever
    /// showed up after a full app relaunch flushed the cache.
    func loadDrawingPads() {
        guard let backendCoupleID else { return }
        myDrawingURL = Self.cacheBusted(BackendService.drawingPadPublicURL(coupleID: backendCoupleID, personID: currentUser.id))
        partnerDrawingURL = Self.cacheBusted(BackendService.drawingPadPublicURL(coupleID: backendCoupleID, personID: partner.id))
    }

    private static func cacheBusted(_ url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = [URLQueryItem(name: "v", value: "\(Int(Date().timeIntervalSince1970 * 1000))")]
        return components.url ?? url
    }

    /// Re-checks the state-derived review milestones (partner connected, first flight/trip/
    /// memory) and surfaces `pendingReviewMilestone` for the first newly-crossed one still
    /// eligible. Safe to call as often as needed — a no-op once a given milestone's already
    /// shown once, or the user's already said yes to any of them. "First game results" isn't
    /// state AppModel tracks directly, so that one's raised via `noteReviewMilestone(_:)` from
    /// `GameResultsView` instead.
    func checkReviewMilestones() {
        guard pendingReviewMilestone == nil else { return }
        if partnerConnected, ReviewPromptService.markShownIfEligible(.partnerConnected) {
            pendingReviewMilestone = .partnerConnected
        } else if !flights.isEmpty, ReviewPromptService.markShownIfEligible(.firstFlight) {
            pendingReviewMilestone = .firstFlight
        } else if !trips.isEmpty, ReviewPromptService.markShownIfEligible(.firstTrip) {
            pendingReviewMilestone = .firstTrip
        } else if !memories.isEmpty, ReviewPromptService.markShownIfEligible(.firstMemory) {
            pendingReviewMilestone = .firstMemory
        }
    }

    /// For the one milestone AppModel can't derive from its own state.
    func noteReviewMilestone(_ milestone: ReviewMilestone) {
        guard pendingReviewMilestone == nil, ReviewPromptService.markShownIfEligible(milestone) else { return }
        pendingReviewMilestone = milestone
    }

    // MARK: - Games: Daily Activity + topic browsing

    /// Fetches (or creates, server-side) today's Daily Activity session and refreshes the
    /// streak — called when the Games hub appears, not at launch, since it's Games-specific.
    func startOrResumeDailyQuestion() async {
        if let sessionID = try? await BackendService.getDailyQuestionSession() {
            todaysDailySessionID = sessionID
            if let detail = try? await BackendService.fetchGameSession(id: sessionID),
               let round = detail.rounds.first, case let .discuss(topic)? = detail.content[round.contentID] {
                todaysDailyQuestionText = topic.topic
            }
        }
        await refreshDailyStreak()
    }

    func refreshDailyStreak() async {
        if let streak = try? await BackendService.fetchDailyStreak() {
            dailyStreak = streak.current
            longestDailyStreak = streak.longest
        }
    }

    /// Populates `gameDecks`/`deckProgress` once per app session (cheap to recheck — both are
    /// simple nil-guards) for the Games hub's topic list and progress bars.
    func loadGameDecksIfNeeded() async {
        guard gameDecks == nil else { return }
        await refreshGameDecks()
    }

    /// Re-fetches unconditionally — called after starting/resetting a deck session so its
    /// progress updates immediately rather than waiting for the next cold load.
    func refreshGameDecks() async {
        async let decks = BackendService.fetchGameDecks()
        async let progress = BackendService.fetchDeckProgress()
        gameDecks = try? await decks
        deckProgress = try? await progress
    }

    /// All of this topic's decks, in curated order — Plus members see Premium-tier decks too now
    /// (they just show an unlock badge, see `isDeckLocked(_:)`), so this no longer filters by
    /// tier the way it originally did.
    func decks(for topic: GameTopic) -> [GameDeck] {
        (gameDecks ?? [])
            .filter { $0.topic == topic.rawValue }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// True if this deck requires a higher tier than the couple currently has — drives the
    /// unlock badge + premium-gate screen rather than hiding the deck outright.
    func isDeckLocked(_ deck: GameDeck) -> Bool {
        deck.tier == "premium" && subscriptionTier != "premium"
    }

    /// Every deck of this game type, across every topic — powers "tap a game type card, see all
    /// its decks" browsing, as opposed to `decks(for topic:)`'s single-topic scoping.
    func decks(ofType gameType: GameType) -> [GameDeck] {
        (gameDecks ?? []).filter { $0.gameType == gameType }
    }

    /// How many of this topic's decks the couple has started at least once — `nil` until
    /// `loadGameDecksIfNeeded()` has completed.
    func topicProgress(_ topic: GameTopic) -> (played: Int, total: Int)? {
        guard gameDecks != nil else { return nil }
        let topicDecks = decks(for: topic)
        guard !topicDecks.isEmpty else { return nil }
        let progress = deckProgress ?? [:]
        let playedCount = topicDecks.filter { progress[$0.id] != nil }.count
        return (playedCount, topicDecks.count)
    }

    /// Only available once paired — there's no couple to namespace the storage path under
    /// beforehand, and no partner pad to make the feature meaningful yet.
    func saveMyDrawing(imageData: Data) async {
        guard let backendCoupleID else { return }
        let uploadedURL = try? await BackendService.uploadDrawingPad(coupleID: backendCoupleID, personID: currentUser.id, imageData: imageData)
        myDrawingURL = uploadedURL
        if uploadedURL != nil {
            Analytics.capture(Analytics.Event.doodleSave)
            Task { await BackendService.notifyPartner(event: .drawingSaved) }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        }
    }

    /// Adopts real couple/trip/memory rows from the backend, flushing anything that was added
    /// locally before pairing completed (drafted during onboarding, or via the home screen's
    /// "add a trip"/"add a memory" cards while still solo).
    private func adopt(_ state: BackendService.CoupleState) async {
        let localOnlyTrips = trips.filter { pendingTripIDs.contains($0.id) }
        let localOnlyMemories = memories.filter { pendingMemoryIDs.contains($0.id) }

        couple = state.couple
        backendCoupleID = state.couple.id
        trips = state.trips
        memories = state.memories
        flights = state.flights
        partnerConnected = true
        hasCouple = true
        isSubscriptionActive = state.subscriptionActive
        subscriptionTier = state.subscriptionTier

        var stillPendingTrips = Set<Trip.ID>()
        for trip in localOnlyTrips {
            // Trips drafted before pairing (e.g. onboarding's "add first flight") were built
            // against a placeholder partner id that never existed as a real profile — remap
            // to the now-real partner so the FK on `trips.traveler_id` doesn't reject it.
            var tripToInsert = trip
            if tripToInsert.travelerID != state.couple.partnerA.id && tripToInsert.travelerID != state.couple.partnerB.id {
                tripToInsert.travelerID = state.couple.partnerB.id
            }
            do {
                try await BackendService.insertTrip(coupleID: state.couple.id, trip: tripToInsert)
            } catch {
                stillPendingTrips.insert(trip.id)
            }
            trips.append(tripToInsert)
        }
        pendingTripIDs = stillPendingTrips

        var stillPendingMemories = Set<Memory.ID>()
        for memory in localOnlyMemories {
            var synced = memory
            do {
                var photoPaths: [String] = []
                for imageData in pendingMemoryPhotoData[memory.id] ?? [] {
                    photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: state.couple.id, memoryID: memory.id, imageData: imageData))
                }
                synced.photos = try await BackendService.insertMemory(coupleID: state.couple.id, memory: memory, photoPaths: photoPaths)
                pendingMemoryPhotoData.removeValue(forKey: memory.id)
                // Now durably on the backend — the local disk copy (and its cached photo
                // files) was only ever a stand-in until this succeeded.
                PendingMemoryStore.remove(id: memory.id)
            } catch {
                stillPendingMemories.insert(memory.id)
            }
            memories.append(synced)
        }
        pendingMemoryIDs = stillPendingMemories
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }

    /// Called once account creation succeeds — now happens *before* the paywall/trial screens
    /// rather than after, so a real account exists to tie the subscription to. Persists
    /// everything collected during the default onboarding flow (situation/frequency/
    /// attribution/goals stay local to `OnboardingModel` for analytics-style use later; names/
    /// cities/photos/drafted flight apply here) — nothing could be written to Supabase before
    /// a session existed. Deliberately does **not** set `hasCouple = true`: `RootView` swaps
    /// straight to `MainTabView` the instant that flips, which would skip the paywall/trial
    /// screens still left to show. `finishOnboarding()` does that final flip once they're done.
    ///
    /// If a real couple already exists (the partner redeemed an invite in a race, or this is
    /// the preserved deep-link path resuming a session that already finished pairing), there's
    /// nothing left to onboard, so this does finish immediately — a narrow edge case where a
    /// returning user skips straight past the paywall.
    func applyOnboardingAccount(_ onboarding: OnboardingModel) async {
        if let state = try? await BackendService.fetchCoupleState() {
            await adopt(state)
            inviteCode = onboarding.inviteCode
            hasCouple = true
            return
        }

        if let userID = BackendService.currentUserID {
            adoptSignedInIdentity(id: userID, firstName: onboarding.firstName)
        }

        if let selfPhotoData = onboarding.selfPhotoData,
           let url = try? await BackendService.uploadAvatar(imageData: selfPhotoData) {
            couple.partnerA.avatarURL = url
        }
        if let partnerPhotoData = onboarding.partnerPhotoData,
           let url = try? await BackendService.uploadPartnerAvatar(imageData: partnerPhotoData) {
            couple.partnerB.avatarURL = url
        }

        if let homeCity = onboarding.homeCity {
            try? await BackendService.updateHomeCity(homeCity)
            couple.partnerA.homeCity = homeCity
        }

        if !onboarding.partnerName.isEmpty {
            try? await BackendService.updatePartnerNickname(onboarding.partnerName)
            couple.partnerB.name = onboarding.partnerName
        }
        if let partnerCity = onboarding.partnerCity {
            try? await BackendService.updatePartnerHomeCityGuess(partnerCity)
            couple.partnerB.homeCity = partnerCity
        }

        if let anniversaryDate = onboarding.anniversaryDate {
            try? await BackendService.updateAnniversaryDate(anniversaryDate)
            couple.startedDatingOn = anniversaryDate
        }

        inviteCode = onboarding.inviteCode
    }

    /// The actual last step of onboarding — called once the paywall/trial flow finishes, so
    /// `RootView` lands the user in `MainTabView`. Account creation already happened earlier
    /// via `applyOnboardingAccount`.
    func finishOnboarding() {
        hasCouple = true
    }

    /// Creates a trip with no flight attached — flights are never self-reported (see
    /// `AeroFlightService.addFlight`/`LiveActivityManager`); callers that have a real,
    /// AeroAPI-resolved `AeroFlightCandidate` in hand should follow up with
    /// `AeroFlightService.addFlight(faFlightId:tripID:notifyMe:)` once this trip exists,
    /// exactly as `AddFirstFlightView`/`AddTripDetailsView` already do.
    @discardableResult
    func addTrip(origin: Place, destination: Place, departureDate: Date, arrivalDate: Date, traveler: TripTraveler, category: TripCategory) async -> Trip {
        let travelerID = traveler == .partner ? partner.id : currentUser.id
        let distance = Geo.distanceKm(origin.coordinate, destination.coordinate)

        let trip = Trip(
            travelerID: travelerID,
            origin: origin,
            destination: destination,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            category: category,
            distanceKm: distance
        )

        trips.append(trip)
        checkReviewMilestones()
        Analytics.capture(Analytics.Event.tripCreate, properties: ["trip_category": category.rawValue])

        if let backendCoupleID {
            do {
                try await BackendService.insertTrip(coupleID: backendCoupleID, trip: trip)
                Task { await BackendService.notifyPartner(event: .tripAdded, detail: "\(origin.city) to \(destination.city)") }
            } catch {
                pendingTripIDs.insert(trip.id)
            }
        } else {
            pendingTripIDs.insert(trip.id)
        }

        return trip
    }

    /// Re-pulls the full flight list from the backend — called after the Add Flight search
    /// flow resolves a real AeroAPI-tracked flight (via the `add-flight` Edge Function, which
    /// writes the row server-side, so there's nothing to merge locally) and by
    /// `FlightDetailView` after an on-demand refresh.
    func refreshFlights() async {
        guard let backendCoupleID else { return }
        if let fresh = try? await BackendService.fetchFlights(coupleID: backendCoupleID) {
            flights = fresh
            for index in trips.indices {
                trips[index].flight = fresh.first { $0.tripID == trips[index].id }
            }
            await LiveActivityManager.shared.reconcileOnLaunch(with: fresh)
            await LiveActivityManager.shared.syncActivities(
                for: fresh,
                travelerName: { [weak self] flight in
                    guard let self else { return "" }
                    return isReunion(flight) ? partner.name : currentUser.name
                },
                isReunion: isReunion
            )
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
            checkReviewMilestones()
        }
    }

    /// Stops tracking a flight entirely (swipe-to-remove on the Trips tab). Re-runs
    /// `refreshFlights()` afterward rather than just filtering `flights` locally so the Live
    /// Activity sync/reconcile logic there — which already ends an Activity for any flight that
    /// disappeared from the fetched list — handles cleanup without duplicating that logic here.
    func deleteFlight(_ flight: Flight) async {
        try? await BackendService.deleteFlight(id: flight.id)
        Analytics.capture(Analytics.Event.flightDelete)
        await refreshFlights()
    }

    /// "Reunion" framing (the app's existing romantic language for "your partner is on their
    /// way to you") applies whenever the signed-in user isn't the one who added/is tracking
    /// this flight — defaults to true when `createdBy` is unset (e.g. an older row) since most
    /// tracked flights are the partner's.
    private func isReunion(_ flight: Flight) -> Bool {
        guard let createdBy = flight.createdBy else { return true }
        return createdBy != currentUser.id
    }

    /// Freeform trip prep notes — reused by the Flight Detail screen's "Trip checklist" card
    /// rather than inventing a separate checklist feature/table.
    func updateTripNotes(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index].notes = trip.notes
        try? await BackendService.updateTripNotes(tripID: trip.id, notes: trip.notes)
    }

    /// Full edit of a trip's own fields (origin/destination/dates/category/notes) — as opposed
    /// to `updateTripNotes`, which only ever touched notes. Recomputes `distanceKm` since
    /// either city could have changed, and preserves the trip's linked flight (not part of what
    /// this edits).
    func updateTrip(_ trip: Trip) async {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        updated.distanceKm = Geo.distanceKm(trip.origin.coordinate, trip.destination.coordinate)
        updated.flight = trips[index].flight
        trips[index] = updated
        try? await BackendService.updateTrip(updated)
    }

    func deleteTrip(_ trip: Trip) async {
        trips.removeAll { $0.id == trip.id }
        pendingTripIDs.remove(trip.id)
        Analytics.capture(Analytics.Event.tripDelete)
        // `flights.trip_id` has ON DELETE SET NULL server-side — the flight survives
        // untethered, so mirror that locally rather than leaving it pointing at a trip that no
        // longer exists.
        if let flightIndex = flights.firstIndex(where: { $0.tripID == trip.id }) {
            flights[flightIndex].tripID = nil
        }
        guard backendCoupleID != nil else { return }
        try? await BackendService.deleteTrip(id: trip.id)
    }

    /// The only way to attach an already-tracked flight to a trip after the fact — every other
    /// write path for `flight.tripID` (`AeroFlightService.addFlight`) only ever sets it once,
    /// at add-flight time.
    func linkFlight(_ flight: Flight, to trip: Trip) async {
        guard let flightIndex = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[flightIndex].tripID = trip.id
        if let tripIndex = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[tripIndex].flight = flights[flightIndex]
        }
        try? await BackendService.setFlightTrip(flightID: flight.id, tripID: trip.id)
    }

    func unlinkFlight(_ flight: Flight) async {
        guard let flightIndex = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        let tripID = flights[flightIndex].tripID
        flights[flightIndex].tripID = nil
        if let tripID, let tripIndex = trips.firstIndex(where: { $0.id == tripID }) {
            trips[tripIndex].flight = nil
        }
        try? await BackendService.setFlightTrip(flightID: flight.id, tripID: nil)
    }

    /// Same gap `linkFlight`/`unlinkFlight` closed for `tripID` — travelers were also only ever
    /// set once, at add-flight time, with no way to change them afterward. Pass an empty array
    /// to clear (e.g. neither partner is confirmed as the traveler yet); pass both ids when
    /// they're travelling together.
    func setFlightTravelers(_ flight: Flight, travelerIDs: [UUID]) async {
        guard let index = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[index].travelerIDs = travelerIDs
        if let tripID = flights[index].tripID, let tripIndex = trips.firstIndex(where: { $0.id == tripID }) {
            trips[tripIndex].flight = flights[index]
        }
        try? await BackendService.setFlightTravelers(flightID: flight.id, travelerIDs: travelerIDs)
    }

    /// Memories have no automatic trip association (no place/date matching) — linking is
    /// always this explicit, user-driven action from Trip Details.
    func linkMemory(_ memory: Memory, to trip: Trip) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].tripID = trip.id
        try? await BackendService.setMemoryTrip(memoryID: memory.id, tripID: trip.id)
    }

    func unlinkMemory(_ memory: Memory) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].tripID = nil
        try? await BackendService.setMemoryTrip(memoryID: memory.id, tripID: nil)
    }

    /// Registers this device's APNs token against the signed-in profile so
    /// `send-flight-notification` (server-side) has somewhere to deliver to. Safe to call
    /// repeatedly — the backend upserts on the token itself.
    func registerPushToken(_ tokenData: Data) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await BackendService.registerDeviceToken(token, environment: environment)
    }

    @discardableResult
    func addMemory(title: String, place: Place?, date: Date, note: String, imagesData: [Data]) async -> Memory {
        let memory = Memory(title: title, place: place, date: date, note: note)
        Analytics.capture(Analytics.Event.memoryCreate, properties: ["photo_count": imagesData.count])

        guard let backendCoupleID else {
            // Persisted to disk (not just kept in memory) — this is the only durable copy
            // until a partner joins, and the returned memory's photos already point at local
            // files so they show immediately instead of staying blank until upload.
            let persisted = PendingMemoryStore.save(memory: memory, photosData: imagesData)
            memories.append(persisted)
            pendingMemoryIDs.insert(persisted.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[persisted.id] = imagesData }
            checkReviewMilestones()
            return persisted
        }

        memories.append(memory)
        checkReviewMilestones()

        do {
            var photoPaths: [String] = []
            for imageData in imagesData {
                photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
            }
            let photos = try await BackendService.insertMemory(coupleID: backendCoupleID, memory: memory, photoPaths: photoPaths)
            if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                memories[index].photos = photos
            }
            Task { await BackendService.notifyPartner(event: .memoryAdded, detail: title) }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        } catch {
            pendingMemoryIDs.insert(memory.id)
            if !imagesData.isEmpty { pendingMemoryPhotoData[memory.id] = imagesData }
        }

        return memories.first { $0.id == memory.id } ?? memory
    }

    /// Edits an existing memory's fields in place, optionally appending new photos in the
    /// same call — both persisted best-effort, matching `addMemory`'s error handling.
    func updateMemory(_ memory: Memory, newImagesData: [Data] = []) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }

        guard let backendCoupleID, !pendingMemoryIDs.contains(memory.id) else {
            // Still pending (never synced) — everything happens locally, same as the initial
            // add: new photos join the accumulated pending data and get re-persisted, so the
            // edit shows immediately and survives a relaunch. Without this, editing a pending
            // memory before a partner joins silently dropped any newly-added photos (the
            // synced-path branch below only uploads when a couple already exists) and never
            // updated the on-disk copy, so the *previous* version would come back after a kill.
            var accumulatedPhotoData = pendingMemoryPhotoData[memory.id] ?? []
            accumulatedPhotoData.append(contentsOf: newImagesData)
            let persisted = PendingMemoryStore.save(memory: memory, photosData: accumulatedPhotoData)
            memories[index] = persisted
            pendingMemoryPhotoData[memory.id] = accumulatedPhotoData.isEmpty ? nil : accumulatedPhotoData
            return
        }

        memories[index] = memory

        do {
            try await BackendService.updateMemory(memory)
            if !newImagesData.isEmpty {
                var photoPaths: [String] = []
                for imageData in newImagesData {
                    photoPaths.append(try await BackendService.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memory.id, imageData: imageData))
                }
                let newPhotos = try await BackendService.addMemoryPhotos(memoryID: memory.id, photoPaths: photoPaths, startingPosition: memory.photos.count)
                memories[index].photos.append(contentsOf: newPhotos)
            }
        } catch {
            // Best-effort for now; local edit stands even if the write failed.
        }
    }

    func removePhoto(_ photo: MemoryPhoto, from memory: Memory) async {
        guard let index = memories.firstIndex(where: { $0.id == memory.id }) else { return }
        memories[index].photos.removeAll { $0.id == photo.id }

        guard !pendingMemoryIDs.contains(memory.id) else {
            // Re-derive the remaining photo bytes from their still-valid local files and
            // re-persist — otherwise a removed photo could reappear on the next pending edit
            // (updateMemory would still find it in the stale pendingMemoryPhotoData) or after
            // a relaunch (the on-disk manifest would still list it).
            let remainingData = memories[index].photos.compactMap { try? Data(contentsOf: $0.url) }
            let persisted = PendingMemoryStore.save(memory: memories[index], photosData: remainingData)
            memories[index] = persisted
            pendingMemoryPhotoData[memory.id] = remainingData.isEmpty ? nil : remainingData
            return
        }

        try? await BackendService.deleteMemoryPhoto(id: photo.id, path: photo.path)
    }

    func deleteMemory(_ memory: Memory) async {
        memories.removeAll { $0.id == memory.id }
        pendingMemoryIDs.remove(memory.id)
        pendingMemoryPhotoData.removeValue(forKey: memory.id)
        PendingMemoryStore.remove(id: memory.id)
        Analytics.capture(Analytics.Event.memoryDelete)
        guard backendCoupleID != nil else { return }
        try? await BackendService.deleteMemory(id: memory.id, photoPaths: memory.photos.map(\.path))
    }

    /// Only ever writes the signed-in user's own city — RLS blocks updating a partner's
    /// profile row, so there's no "set it on their behalf" path anymore.
    func setHomeCity(for personID: Person.ID, city: Place) async {
        guard personID == currentUser.id else { return }
        do {
            try await BackendService.updateHomeCity(city)
            couple.partnerA.homeCity = city
        } catch {
            // Best-effort for now; the picker just won't reflect the change.
        }
    }

    /// `RootView`'s foreground-triggered current-city refresh lands here once
    /// `HomeLocationService` resolves a fresh fix — compares by city/country name, not
    /// `Place.id`, since a new location fix builds a brand new `Place` (fresh random id) on
    /// every call even when the resolved city hasn't actually changed, and an id comparison
    /// would rewrite the backend row (and spuriously invalidate `HomeView`'s per-city-id weather
    /// cache) on every single foreground for no reason.
    func updateCurrentCityIfChanged(_ place: Place) async {
        guard place.city != couple.partnerA.homeCity?.city || place.country != couple.partnerA.homeCity?.country else { return }
        await setHomeCity(for: currentUser.id, city: place)
    }

    /// Sets the signed-in user's identity as soon as an account exists, so any trip drafted
    /// during the rest of onboarding (before pairing) carries the real profile id rather
    /// than a throwaway placeholder.
    func adoptSignedInIdentity(id: UUID, firstName: String) {
        couple.partnerA = Person(
            id: id,
            name: firstName.isEmpty ? "You" : firstName,
            homeCity: couple.partnerA.homeCity,
            accentColor: Person.palette[1]
        )
    }
}
