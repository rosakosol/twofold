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
import Supabase
import UserNotifications
import WidgetKit

private extension ISO8601DateFormatter {
    /// Date only, for the dormancy touch throttle — see `AppModel.touchLastActive()`. Comparing
    /// day strings rather than timestamps means the throttle rolls over at local midnight and
    /// never has to reason about how long ago "a day" was.
    static let dormancyDay: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }()
}

@Observable
final class AppModel {
    var isLoadingSession = true

    /// Advances every time `resetAccountScopedState()` runs, which is every way an account ends on
    /// this device: sign-out, deletion, and a deleted account found at sign-in.
    ///
    /// For state this class cannot reach. `OnboardingCoordinatorView` keeps its `OnboardingModel`
    /// as `@State`, and stays mounted across a sign-out because `hasCouple` is false on both sides
    /// of it. Nothing reset that model, so signing out from the onboarding paywall left a
    /// signed-out user on the paywall (a purchase there lands on RevenueCat's anonymous id), and
    /// "Go back" or "Start a new signup" kept the previous account's names, photos and invite code
    /// for whoever started next. The coordinator watches this and builds a fresh model.
    private(set) var accountGeneration = 0

    /// Whether the account that was signed in at `generation` still is. Work that awaits the
    /// network captures `accountGeneration` before it leaves and checks this when it comes back,
    /// so an answer for an account that has since signed out is dropped rather than applied to
    /// whoever is signed in now (CORE-4).
    private func isCurrent(_ generation: Int) -> Bool {
        generation == accountGeneration
    }
    /// Set when "Sign in" produced a brand-new account instead of resuming an existing one, which
    /// is what Apple's Hide My Email does to anyone who already signed up with their real address:
    /// the relay `...@privaterelay.appleid.com` is a different email, so Supabase makes a different
    /// user. The old account still exists, still holds the couple and the history, and nothing
    /// said so - the person simply arrived in an empty app. `OnboardingCoordinatorView` shows this
    /// once and clears it.
    var signedInToNewAccountMessage: String?
    /// Set by `loadSignedInState()` when it finds a session belonging to an already-deleted
    /// account and signs it back out. `SignInView`/`WelcomeView` read this once to show the
    /// user why they landed back at sign-in instead of their previous session resuming.
    var accountDeletedMessage: String?
    /// Home-screen drawing pads — only meaningful once paired, since there's no partner pad to
    /// compare against (and nowhere real to save to) before then.
    var myDrawingURL: URL?
    var partnerDrawingURL: URL?

    // MARK: - Child stores
    //
    // Each holds one part of the account's state and puts it back with its own `reset()`. Read
    // them directly: `appModel.subscription.tier`, `appModel.travel.trips`.

    /// Subscribed or not, which tier, and who pays.
    let subscription = SubscriptionState()
    /// The review prompt, invite nudge, celebration, checklist, and the notices.
    let prompts = PromptsState()
    /// The daily question, the streak, the decks and how far through them the couple is.
    let games = GamesState()
    /// Trips, flights and memories, and everything that adds to or changes them.
    let travel = TravelStore()
    /// The couple itself, whether there is one, onboarding's progress, and connection requests.
    let session = CoupleSession()

    /// Every child store holding account state — what `resetAccountScopedState()` resets.
    /// `AccountScopedStoreTests` fails if a store is added above and not here.
    var accountScopedStores: [any AccountScopedStore] {
        [session, subscription, prompts, games, travel]
    }

    /// Serializes `adopt(_:)` — it can legitimately be entered from three places (launch's
    /// `loadSignedInState`, onboarding's `applyOnboardingAccount`, and Home's
    /// `refreshCoupleStateIfNeeded`, itself fired from both `.onAppear` and
    /// `.onChange(of: scenePhase)`), and `hasCouple` flips true partway through the function body
    /// — so a second call can start while the first is still mid-flight. Without this, two
    /// interleaved calls can both capture the same pending trip/memory before either writes back,
    /// double-inserting it server-side and leaving a duplicate local copy.
    private var inFlightAdopt: Task<Void, Never>?

    /// The trip, memory and profile calls below go through this rather than `BackendService`
    /// directly, so a unit test can hand in a backend that fails or answers on cue.
    @ObservationIgnored var backend: any CoupleDataBackend = LiveCoupleDataBackend()

    /// What `signOut()` and `deleteAccount()` call on the way out, so a test can check the order.
    @ObservationIgnored var sessionTeardown: any SessionTeardown = LiveSessionTeardown()

    /// The couple-state read behind `refreshCoupleStateIfNeeded()`, so a test can hold it in the
    /// air while something else — a sign-out — happens.
    @ObservationIgnored var fetchCoupleStateOutcome: () async -> CoupleStateOutcome = { await CoupleStateOutcome.fetch() }

    init() {
        travel.host = self
        games.isPartnerConnected = { [weak self] in self?.session.partnerConnected ?? false }
        // The Daily question widget reads this state; the snapshot is otherwise only rewritten on
        // launch and on other changes, so an answer would not reach the Home Screen until then.
        games.onDailyQuestionChanged = { [weak self] in
            guard let self else { return }
            Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        }
    }

    // MARK: - Outbox

    /// True while `syncPendingWrites()` is draining the outbox. A write made meanwhile is queued
    /// and left for that pass to send, rather than sent alongside it and risking the two landing
    /// out of order.
    ///
    /// Scoped to the account the pass started for. A plain flag outlived sign-out whenever a send
    /// was in the air at the time, and the next account's edits — from `commit` and from its own
    /// passes — were all left for a pass that had stopped working for anyone.
    private var syncingPendingWritesGeneration: Int?
    private var isSyncingPendingWrites: Bool { syncingPendingWritesGeneration == accountGeneration }

    /// Every refresh replaces `trips`/`memories`/`flights` (and `adopt` the couple's own fields)
    /// with the server's copy, which knows nothing of an edit that hasn't been sent yet — or that
    /// is in the air right now. Re-applying the outbox afterwards is what keeps such an edit on
    /// screen instead of silently reverting it until the next refresh catches up. It replaces the
    /// in-memory list of in-flight edits this used to keep, which forgot an edit the moment its
    /// one attempt failed.
    func reapplyPendingWrites() {
        for entry in PendingWriteStore.all() {
            apply(entry.write)
        }
    }

    /// The local half of a write: what the screen should show once it has landed.
    private func apply(_ write: PendingWrite) {
        switch write {
        case .tripEdit, .trip, .tripNotes, .flightTrip, .flightTravelers, .memoryEdit, .memory,
             .memoryTrip, .memoryPhotos, .removeMemoryPhoto:
            travel.apply(write)
        case .firstName(let name):
            session.couple.partnerA.name = name
        case .partnerNickname(let name):
            session.couple.partnerB.name = name
        case .partnerHomeCity(let city):
            session.couple.partnerB.homeCity = city
        case .homeCity(let city):
            session.couple.partnerA.homeCity = city
        case .anniversaryDate(let date):
            session.couple.startedDatingOn = date
        }
    }

    /// Applies a write here, puts it in the outbox and sends it.
    ///
    /// Queued before it is sent, not after it fails: an app killed mid-request still has it, and a
    /// refresh landing while it is in the air re-applies it. On success it leaves the queue. On a
    /// failure that is not a refusal it stays, and `syncPendingWrites()` sends it at the next
    /// launch, foreground or reconnect — this is what makes editing work offline, which the code
    /// used to promise ("the write lands later") without anything ever sending it again. A refusal
    /// will never land, so it leaves the queue and `onRefusal` undoes the local half.
    func commit(_ write: PendingWrite, onRefusal: () -> Void) async {
        let entry = PendingWriteStore.add(write)
        apply(write)
        guard !isSyncingPendingWrites, travel.isReadyToSend(write) else { return }
        let generation = accountGeneration
        // Undoing it on the next account's screen would be undoing something it never did.
        if await send(entry) == .refused, isCurrent(generation) { onRefusal() }
    }

    private enum SendOutcome { case sent, refused, failed }

    private func send(_ entry: PendingWriteEntry) async -> SendOutcome {
        do {
            try await deliver(entry.write)
            PendingWriteStore.remove(id: entry.id)
            return .sent
        } catch {
            guard BackendService.isPermanentRefusal(error) else { return .failed }
            PendingWriteStore.remove(id: entry.id)
            return .refused
        }
    }

    /// The network half of a write.
    private func deliver(_ write: PendingWrite) async throws {
        switch write {
        case .tripEdit(let edit):
            try await backend.updateTrip(edit)
        case .trip(let trip):
            try await backend.updateTrip(TripEdit(allFieldsOf: trip))
        case let .tripNotes(tripID, notes):
            try await backend.updateTripNotes(tripID: tripID, notes: notes)
        case let .flightTrip(flightID, tripID):
            try await backend.setFlightTrip(flightID: flightID, tripID: tripID)
        case let .flightTravelers(flightID, travelerIDs):
            try await backend.setFlightTravelers(flightID: flightID, travelerIDs: travelerIDs)
        case .memoryEdit(let edit):
            try await backend.updateMemory(edit)
        case .memory(let memory):
            try await backend.updateMemory(MemoryEdit(allFieldsOf: memory))
        case let .memoryTrip(memoryID, tripID):
            try await backend.setMemoryTrip(memoryID: memoryID, tripID: tripID)
        case let .memoryPhotos(memoryID, photos):
            // A photo can only be stored under a couple. Not a refusal: it stays queued.
            guard let backendCoupleID else { throw URLError(.userAuthenticationRequired) }
            // Several round trips, so the one place a sign-out can land between two of them and
            // the next is sent as somebody else. Thrown as a failure, not a refusal: nothing is
            // undone, and the queue it came from has already been cleared.
            let generation = accountGeneration
            var photoPaths: [String] = []
            for photo in photos {
                guard let data = PendingWriteStore.photoData(id: photo.id) else { continue }
                photoPaths.append(try await backend.uploadMemoryPhoto(coupleID: backendCoupleID, memoryID: memoryID, imageData: data))
                guard isCurrent(generation) else { throw CancellationError() }
            }
            // Positions after the photos the server already has, read now rather than when the
            // write was queued: others may have been added or removed since.
            let startingPosition = travel.memories.first { $0.id == memoryID }?.photos.filter { !$0.isPending }.count ?? 0
            let uploaded = try await backend.addMemoryPhotos(memoryID: memoryID, photoPaths: photoPaths, startingPosition: startingPosition)
            guard isCurrent(generation) else { throw CancellationError() }
            // Looked up again after the awaits, by id: a refresh may have replaced the array.
            if let index = travel.memories.firstIndex(where: { $0.id == memoryID }) {
                let standIns = Set(photos.map(\.id))
                travel.memories[index].photos.removeAll { standIns.contains($0.id) }
                travel.memories[index].photos.append(contentsOf: uploaded)
            }
        case let .removeMemoryPhoto(_, photoID, path):
            try await backend.deleteMemoryPhoto(id: photoID, path: path)
        case .firstName(let name):
            try await backend.updateFirstName(name)
        case .partnerNickname(let name):
            try await backend.updatePartnerNickname(name)
        case .partnerHomeCity(let city):
            try await backend.updatePartnerHomeCityGuess(city)
        case .homeCity(let city):
            try await backend.updateHomeCity(city)
        case .anniversaryDate(let date):
            // Whichever is authoritative when it is sent, which may not be what it was when it was
            // made: pairing in between moves the date onto the couple (see `updateAnniversaryDate`).
            if let backendCoupleID {
                try await backend.updateCoupleAnniversaryDate(coupleID: backendCoupleID, date: date)
            } else {
                try await backend.updateAnniversaryDate(date)
            }
        }
    }

    /// Sends what is in the outbox, oldest first, then the game answers waiting in theirs
    /// (`GameResponseOutbox`). Called at launch, on returning to the foreground and on
    /// reconnecting — through `performAdopt` for a couple, and from the solo paths directly.
    ///
    /// Stops at the first failure that is not a refusal: the connection is down, and the rest
    /// would fail the same way one timeout at a time. A refusal here is a write made earlier that
    /// will never land; it leaves the queue, and the next refresh shows what the server has.
    func syncPendingWrites() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing sent
        guard !isSyncingPendingWrites else { return }
        let generation = accountGeneration
        syncingPendingWritesGeneration = generation
        defer { if syncingPendingWritesGeneration == generation { syncingPendingWritesGeneration = nil } }

        var tried = Set<PendingWriteEntry.ID>()
        var refusedAny = false
        var connectionFailed = false
        // Re-read each time round, so a write queued while this runs is sent by this pass.
        while let entry = PendingWriteStore.all().first(where: { !tried.contains($0.id) && travel.isReadyToSend($0.write) }) {
            tried.insert(entry.id)
            let outcome = await send(entry)
            // Signed out while that was in the air. What is in the queue now is the next
            // account's, for its own pass to send as itself.
            guard isCurrent(generation) else { return }
            if outcome == .failed { connectionFailed = true; break }
            if outcome == .refused {
                refusedAny = true
                // Its stand-in photos point at files that have just been deleted.
                if case let .memoryPhotos(memoryID, photos) = entry.write,
                   let index = travel.memories.firstIndex(where: { $0.id == memoryID }) {
                    let standIns = Set(photos.map(\.id))
                    travel.memories[index].photos.removeAll { standIns.contains($0.id) }
                }
            }
        }
        if refusedAny {
            writeRefusedMessage = "Some changes you made while offline couldn't be saved."
        }
        // Game answers and puzzle results queued with no game screen left open to send them —
        // their own queue, sent at the same moments (GAME-3). Not after a write above has just
        // timed out: these would only time out the same way.
        if !connectionFailed {
            await GameResponseOutbox.flush()
        }
    }

    var currentUser: Person { session.couple.partnerA }
    var partner: Person { session.couple.partnerB }

    var needsPartnerInvite: Bool { !session.partnerConnected }
    var needsFirstTrip: Bool { travel.trips.isEmpty }
    var needsFirstFlight: Bool { !travel.trips.contains { !$0.flights.isEmpty } }
    /// Split in two, because only one of the two missing cities is the current user's to fix.
    ///
    /// This was a single `needsHomeCities` — "either of them is missing" — which put "Turn on
    /// location access" in front of people who had already turned it on. The city that was
    /// missing was their partner's, and nothing they did on this device was ever going to fill
    /// it in, so the row sat there permanently with no way to complete it.
    var needsOwnHomeCity: Bool { currentUser.homeCity == nil }

    /// Gated on `partnerConnected` so that a solo user is never told they are waiting on somebody
    /// who does not exist yet — `partner` is a placeholder until a couple is formed.
    var needsPartnerHomeCity: Bool { session.partnerConnected && partner.homeCity == nil }

    /// Tells the server this account is in use, at most once a day.
    ///
    /// The dormancy timer (20261029000100) closes accounts nobody has opened in two years, and
    /// this is the only thing that feeds it. `auth.users.last_sign_in_at` cannot: it is stamped on
    /// an actual sign-in, not on the token refreshes that keep somebody signed in indefinitely, so
    /// without this call a person who opens the app every morning would still look untouched since
    /// the day they installed it.
    ///
    /// Throttled on a plain `UserDefaults` date string rather than `@AppStorage`, which is a
    /// `DynamicProperty` and only actually observes anything inside a `View`. Day resolution is
    /// all that is wanted — the value it feeds is measured in months, and a write per foreground
    /// would be a round trip per foreground for nothing.
    ///
    /// Deliberately silent on failure. Missing a day changes nothing (the next foreground stamps
    /// it), and there is no version of "we could not record that you were here" worth interrupting
    /// somebody to say.
    func touchLastActive() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        let key = "dormancy.lastTouchedOn"
        let today = ISO8601DateFormatter.dormancyDay.string(from: .now)
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        do {
            try await BackendService.touchLastActive()
            UserDefaults.standard.set(today, forKey: key)
        } catch {
            // Next foreground tries again.
        }
    }

    // MARK: - Session / backend sync

    /// Called once at launch. Restores a session if one exists and loads real state; leaves
    /// `hasCouple = false` only when there's genuinely no session, so `RootView` routes into
    /// onboarding for a first-time user but never for a returning one who just hasn't paired
    /// with a partner yet (see `loadSignedInState`).
    func restoreSession() async {
        defer { isLoadingSession = false }

        #if DEBUG
        if DemoMode.isOn {
            applyDemoState()
            return
        }
        // Before the cache read below, so the test's account is the one whose cache is looked
        // for — `E2ELaunch` has already emptied the Keychain, so there is no other.
        if let credentials = E2ELaunch.credentials {
            await signInForEndToEndTest(credentials)
        }
        #endif

        // Cache first, always — not only when we already believe we're offline.
        //
        // `BackendService.restoreSession()` awaits `supabase.auth.session`, which refreshes an
        // expired token over the network, and `loadSignedInState()` then makes several more calls
        // in sequence; with no connectivity every one has to time out before the splash clears,
        // measured at ~45s on a cold launch.
        //
        // This used to be gated on `!NetworkMonitor.shared.isConnected`, which never fired at
        // launch: `isConnected` defaults to `true` and `NWPathMonitor` delivers its first real
        // reading asynchronously, so at the instant this runs — the first thing the app does — the
        // monitor still says connected even in airplane mode. The gate was the whole fix, and it
        // was racing something it could never win.
        //
        // Ungated, it doesn't need to win: `currentSession` reads the locally-stored session with
        // no network at all, so an account that has run before shows its cached state immediately
        // and the refresh below overwrites it whenever the network answers. The stale-then-fresh
        // flip that gate existed to avoid is between two states of the same account, usually
        // identical, and lasts as long as one round trip. That is a far smaller cost than a splash
        // screen that never clears — and it covers what the monitor cannot see at all: a captive
        // portal, or a connection too slow to finish.
        if let userID = BackendService.currentUserID,
           let cached = OfflineSessionCache.restore(for: userID) {
            applyCachedSession(cached)
            session.hasCouple = true
            isLoadingSession = false
        }

        guard await BackendService.restoreSession() != nil else { return }
        await loadSignedInState()
    }

    #if DEBUG
    /// The end-to-end harness's sign-in, standing in for the Apple and Google sheets a UI test
    /// cannot drive. Through `BackendService.signIn` — the same call the email form makes — so the
    /// session lands in the Keychain exactly as a real one does, and `restoreSession` carries on
    /// down its ordinary signed-in path as if this were any returning launch.
    ///
    /// A failure stops the app rather than leaving it on Welcome. The account was created moments
    /// ago by the test itself, so a refusal means the harness is broken, and a test that then
    /// waited thirty seconds for a Home screen would report the wrong thing.
    private func signInForEndToEndTest(_ credentials: (email: String, password: String)) async {
        do {
            try await BackendService.signIn(email: credentials.email, password: credentials.password)
        } catch {
            fatalError("E2E sign-in as \(credentials.email) failed: \(error)")
        }
    }
    #endif

    /// Replays the last-known trips/flights/memories from disk. Only ever called once the live
    /// fetches have already failed, so it can't overwrite fresher server data.
    ///
    /// Anything still pending sync wins over its cached copy: `restorePendingTripsFromDisk()`/
    /// `restorePendingMemoriesFromDisk()` run earlier in `loadSignedInState`, and those are the
    /// user's newest work — a stale server snapshot must not clobber something they added offline
    /// and haven't uploaded yet.
    private func applyCachedTravelData() {
        guard let cached = OfflineDataCache.restore(for: BackendService.currentUserID) else { return }
        let pendingTrips = travel.trips.filter { travel.pendingTripIDs.contains($0.id) }
        let pendingMemories = travel.memories.filter { travel.pendingMemoryIDs.contains($0.id) }
        travel.trips = cached.trips.filter { !travel.pendingTripIDs.contains($0.id) } + pendingTrips
        travel.memories = cached.memories.filter { !travel.pendingMemoryIDs.contains($0.id) } + pendingMemories
        travel.flights = cached.flights
        // Only fill a city that isn't already known — a live value from the backend is better than
        // a cached one, and this also runs on paths where some state is already real.
        if session.couple.partnerA.homeCity == nil { session.couple.partnerA.homeCity = cached.myCity }
        if session.couple.partnerB.homeCity == nil { session.couple.partnerB.homeCity = cached.partnerCity }
        if session.couple.partnerA.avatarURL == nil { session.couple.partnerA.avatarURL = cached.myAvatarURL }
        if session.couple.partnerB.avatarURL == nil { session.couple.partnerB.avatarURL = cached.partnerAvatarURL }
        // The pads' storage paths, so an offline cold launch can find the drawings on disk
        // (HOME-9). Not signed — see `OfflineDataCache.Snapshot.myDrawingURL` — so they only ever
        // reach the disk cache, and the first successful `loadDrawingPads` replaces them.
        if myDrawingURL == nil { myDrawingURL = cached.myDrawingURL }
        if partnerDrawingURL == nil { partnerDrawingURL = cached.partnerDrawingURL }
        // The couple's own fields, and only while `couple` is still the placeholder — once
        // `performAdopt` has run, `couple.id` matches the cached one and the live values stand.
        // `placeholderCouple` has no anniversary, so without this the Stats screen opened offline
        // asking a couple of nine years for the date they had already given.
        if session.couple.id != cached.coupleID {
            if let startedDatingOn = cached.startedDatingOn { session.couple.startedDatingOn = startedDatingOn }
            if session.couple.connectedAt == nil { session.couple.connectedAt = cached.connectedAt }
            if session.couple.maxDistanceKm == nil { session.couple.maxDistanceKm = cached.maxDistanceKm }
        }
        // And anything edited offline and not yet sent wins over its cached copy too, for the
        // same reason.
        reapplyPendingWrites()
        games.applyCachedGameState()
    }

    /// Called any time we know a Supabase session exists — at launch (`restoreSession`), right
    /// after a manual sign-in (`SignInView`), or after `removePartner()` dissolves a couple.
    /// Being authenticated at all means onboarding is already done, regardless of whether a
    /// `couples` row exists yet — so this always ends with `hasCouple = true`, rather than
    /// leaving a solo (unpaired) user to fall back into onboarding just because
    /// `fetchCoupleState` found nothing.
    func loadSignedInState() async {
        // Backstop for a soft-deleted account whose session (or whose Apple/Google identity)
        // can still resolve to a signed-in state — see `BackendService.currentAccountIsDeleted()`.
        // Must run before anything else touches profile/couple state, so a scrubbed, deleted
        // account is never actually adopted and shown.
        if await BackendService.currentAccountIsDeleted() {
            await sessionTeardown.endLiveActivities()
            try? await BackendService.signOut()
            // This path used to stop at the line above, which signs out of the backend and leaves
            // every local cache and every in-memory field belonging to the deleted account exactly
            // where they were. Before `accountDeletedMessage` is set, because clearing wipes it.
            await clearLocalSessionState()
            accountDeletedMessage = "This account has been deleted and can't be signed back into. Create a new account to keep using Twofold."
            isLoadingSession = false
            return
        }
        let generation = accountGeneration
        await retryPendingPushTokenRegistrationIfNeeded()
        try? await BackendService.updateDeviceContext()
        await identifyWithRevenueCat()
        identifyWithPostHog()
        travel.restorePendingMemoriesFromDisk()
        travel.restorePendingTripsFromDisk()
        let outcome = await CoupleStateOutcome.fetch()
        // Signed out while that was in the air: nothing below is for whoever is here now.
        guard isCurrent(generation) else { return }
        if case let .paired(state) = outcome {
            await adopt(state, startedIn: generation)
            // A couple cannot exist without both people having been through onboarding.
            session.needsOnboarding = false
        } else if case .noCouple = outcome, let profile = try? await BackendService.fetchOwnProfile() {
            // Only when the backend actually said so. A failed fetch used to land here too, so a
            // launch on a flaky connection could show a paired couple their solo, unpaired app.
            await adoptSoloProfile(profile, startedIn: generation)
            // Adopted first, so the subscription and tier this account bought on the web are
            // already in hand by the time onboarding starts and can be used to skip the paywall.
            //
            // The local note is consulted as well as the column, and only ever to let somebody
            // *in* — it can admit an account the server still thinks is mid-onboarding, never send
            // one back. That asymmetry is the point: the failure being guarded against is a person
            // stuck outside their own app, so the harm of honouring a stale note (one extra
            // account reaching Home without a partner name) is not the same size as the harm of
            // ignoring a true one.
            // Read before the routing decision below, because it decides which *root* onboarding
            // shows rather than whether it shows at all.
            session.hasSavedOnboardingProgress = profile.hasSavedOnboardingProgress
            let completedLocally = BackendService.currentUserID.map(Self.onboardingCompletedLocally) ?? false
            session.needsOnboarding = Self.shouldRouteToOnboarding(
                serverSaysCompleted: profile.hasCompletedOnboarding,
                completedLocally: completedLocally
            )
            // The retry. This is the only place with both halves in hand — the server's answer and
            // this device's note that it disagrees — so it is the only place that can settle it.
            if !profile.hasCompletedOnboarding, completedLocally, let userID = BackendService.currentUserID {
                do {
                    try await BackendService.markOnboardingCompleted()
                    Self.forgetOnboardingCompletedLocally(for: userID)
                } catch {
                    // Kept, and tried again next launch. Dropping the note here would hand the
                    // person back the trap the note exists to keep them out of.
                }
            }
        } else if let cached = OfflineSessionCache.restore(for: BackendService.currentUserID) {
            // Both reads failed — almost always no network (they're `try?`, so a real outage looks
            // identical to "no rows"). Without this, `isSubscriptionActive` keeps its `false`
            // default while `hasCouple` is set to true just below, and `RootView` drops a paying
            // subscriber onto the non-dismissable paywall.
            applyCachedSession(cached)
            // Same reconciliation the adopt branches get. A cache written before a purchase says
            // `false`, and this is the offline-launch path — the one where nothing else will
            // correct it.
            subscription.isActive = await subscription.resolvedActive(backendSaysActive: cached.active)
            // The cache holds the couple-wide answer and cannot say which partner pays, so the
            // device is the only evidence available here about *this* person. It is also the right
            // evidence: an entitlement this install can prove belongs to the account signed into
            // it. Falling back to false when there is none keeps the delete screen quiet rather
            // than telling the wrong partner to cancel something.
            subscription.viewerHoldsSubscription = await subscription.deviceHoldsEntitlement()
            subscription.markResolved()
            session.hasLoadedCoupleState = true
        }
        // The branches above all await, and the one thing that must not happen after a sign-out
        // landed among them is this line letting the signed-out person back into the app.
        guard isCurrent(generation) else { return }
        // Not `true` outright any more — see `needsOnboarding`, which is the one case where a
        // real session should still land on the onboarding flow rather than the app.
        session.hasCouple = !session.needsOnboarding
        // Resolved here, not only from RootView's launch task.
        //
        // That task runs once, at launch. Someone who opens the app signed out gets an early
        // return from it (`guard hasCouple`) that leaves `hasResolvedOutgoingConnectionRequest`
        // false, and then signs in — at which point `hasCouple` flips true, RootView re-renders,
        // and its paywall-exemption gate holds them on the loading screen forever because nothing
        // remains to resolve the flag. A real sign-in that ends in an infinite beating heart.
        //
        // Tying it to `hasCouple` instead means every path that admits someone to the app resolves
        // it: launch, manual sign-in, and password recovery all end up here. The call is cheap for
        // a paired couple — `refreshPendingOutgoingConnectionRequest` returns without a round trip
        // when `partnerConnected`.
        await session.refreshPendingOutgoingConnectionRequest()
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        checkReviewMilestones()
    }

    /// Unpacks a cached snapshot into the live state — the couple's names, what they've paid for,
    /// and their travel data. Called from both launch paths so there's one definition of what
    /// "the app, from cache" means rather than two that can drift.
    ///
    /// Deliberately doesn't touch `hasCouple` or `isLoadingSession`: what a cache means for routing
    /// differs between a pre-network launch and a post-failure fallback, so those stay with the
    /// caller that knows which it is.
    private func applyCachedSession(_ cached: OfflineSessionCache.Snapshot) {
        subscription.isActive = cached.active
        subscription.tier = cached.tier
        session.partnerConnected = cached.partnerConnected
        if let myName = cached.myName, !myName.isEmpty { session.couple.partnerA.name = myName }
        if let partnerName = cached.partnerName, !partnerName.isEmpty { session.couple.partnerB.name = partnerName }
        prompts.partnerConnectedCelebrationShown = cached.celebrationShown
        prompts.setupChecklistDismissed = cached.checklistDismissed
        travel.restorePendingMemoriesFromDisk()
        travel.restorePendingTripsFromDisk()
        applyCachedTravelData()
    }

    /// Resets to the solo (unpaired) state and repopulates from the caller's own profile —
    /// shared by `loadSignedInState()` (launch/sign-in) and `refreshCoupleStateIfNeeded()`
    /// (an already-connected device discovering the couple was dissolved elsewhere). Reset
    /// first: at launch these are already at their zero-value defaults so it's a no-op, but
    /// reused mid-session this clears the *old* partner's data (partnerConnected,
    /// backendCoupleID, trips/memories/flights, drawing pad URLs) that would otherwise survive
    /// and make a just-dissolved couple still look "connected" in the UI. Trips/memories still in
    /// `pendingTripIDs`/`pendingMemoryIDs` are the exception — they were never tied to any
    /// couple in the first place (added before ever pairing, still only durable via
    /// `PendingTripStore`/`PendingMemoryStore`), so they survive this reset rather than being
    /// discarded along with the dissolved couple's data.
    private func adoptSoloProfile(_ profile: BackendService.OwnProfileState, startedIn generation: Int) async {
        guard isCurrent(generation) else { return }
        await travel.stopFlightsRealtimeSubscription()
        guard isCurrent(generation) else { return }
        if session.partnerConnected {
            let name = session.couple.partnerB.name.isEmpty ? "your partner" : session.couple.partnerB.name
            prompts.partnerDisconnectedMessage = "We're sorry — your connection with \(name) has ended. Nothing has been deleted; your shared trips, memories, and flights are still there, safe and yours to look back on or export anytime from Settings."
        }
        session.partnerConnected = false
        session.backendCoupleID = nil
        travel.trips = travel.trips.filter { travel.pendingTripIDs.contains($0.id) }
        travel.memories = travel.memories.filter { travel.pendingMemoryIDs.contains($0.id) }
        travel.flights = []
        // Unlike every other path that clears `flights`, this one can't just call
        // `refreshFlights()` afterward to reconcile Live Activities — it guards on
        // `backendCoupleID`, which is already nil above. Ending them directly instead, so a
        // flight-tracking Live Activity doesn't keep showing (now stale, since the couple that
        // authorized it no longer exists) until the app happens to background/foreground or
        // relaunch. `endAll`, not a sync against an empty list: that only ended what this run of
        // the app had started or reconciled, which in a fresh process is nothing.
        await LiveActivityManager.shared.endAll()
        guard isCurrent(generation) else { return }
        myDrawingURL = nil
        partnerDrawingURL = nil
        session.couple = CoupleSession.placeholderCouple

        session.couple.partnerA = profile.person
        if let partnerName = profile.partnerName, !partnerName.isEmpty {
            session.couple.partnerB.name = partnerName
        }
        if let partnerHomeCity = profile.partnerHomeCity {
            session.couple.partnerB.homeCity = partnerHomeCity
        }
        if let partnerAvatarURL = profile.partnerAvatarURL {
            session.couple.partnerB.avatarURL = partnerAvatarURL
        }
        if let anniversaryDate = profile.anniversaryDate {
            session.couple.startedDatingOn = anniversaryDate
        }
        // The profile just read is the server's, so a name or city changed offline and not yet
        // sent goes back on top of it — then gets sent, since solo there is no `performAdopt` to.
        reapplyPendingWrites()
        Task { [weak self] in await self?.syncPendingWrites() }
        let subscribed = await subscription.resolvedActive(backendSaysActive: profile.subscriptionActive)
        // Unpaired, so their own row is the only row: whatever access they have is theirs.
        let deviceEntitled = await subscription.deviceHoldsEntitlement()
        guard isCurrent(generation) else { return }
        subscription.apply(
            active: subscribed,
            viewerHolds: profile.subscriptionActive || deviceEntitled,
            tier: profile.subscriptionTier,
            viewerStore: profile.subscriptionStore
        )
        session.hasLoadedCoupleState = true
        // Same reasoning as `performAdopt` — see OfflineSessionCache. Solo (unpaired) here, so
        // partnerConnected is false; restoring that keeps the setup card honest either way.
        OfflineSessionCache.record(
            active: profile.subscriptionActive,
            tier: profile.subscriptionTier,
            userID: BackendService.currentUserID,
            partnerConnected: false,
            myName: profile.person.name,
            partnerName: profile.partnerName,
            celebrationShown: profile.partnerConnectedCelebrationShown,
            checklistDismissed: profile.setupChecklistDismissed
        )
        prompts.partnerConnectedCelebrationShown = profile.partnerConnectedCelebrationShown
        prompts.setupChecklistDismissed = profile.setupChecklistDismissed
        prompts.partnerSubscriptionLapsedPartnerName = profile.partnerSubscriptionLapseShown ? nil : profile.partnerSubscriptionLapsePartnerName
    }

    /// A device's own successful purchase or restore, applied at once — see
    /// `SubscriptionState.markActive(tier:)` — then the lapse notice retired and the widgets told.
    func markSubscriptionActive(tier: String) {
        subscription.markActive(tier: tier)
        // Subscribing is the end of the situation the lapse notice describes, so retire it here
        // rather than waiting for somebody to dismiss it — the card has no dismiss any more. Home
        // hides it the moment `canAddContent` flips; this is what stops a stale name coming back
        // if the same account lapses again later for an unrelated reason.
        prompts.markPartnerSubscriptionLapseAcknowledged()
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
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
        // Never in a test run: see `RevenueCatConfig.configure()`.
        guard !E2ELaunch.isOn, let userID = BackendService.currentUserID else { return }
        if (try? await Purchases.shared.logIn(userID.uuidString)) == nil {
            // One retry — a `logIn` failure here (typically a network blip right at launch/sign-in)
            // is exactly what leaves RevenueCat on its anonymous ID for the rest of the session,
            // which `RootView.deviceHoldsEntitlement`'s `isAnonymous` check exists to stay safe against
            // regardless, but a second attempt costs nothing and fixes the common transient case
            // outright rather than just avoiding its worst consequence.
            _ = try? await Purchases.shared.logIn(userID.uuidString)
        }

        // Puts the account's email on the RevenueCat customer, purely so a person is findable in
        // that dashboard. `app_user_id` is the Supabase UUID and nothing else about the customer
        // identifies them, so answering "why is this subscriber on Premium?" meant copying a UUID
        // out of RevenueCat and querying Postgres with it, every time.
        //
        // `$email` is a reserved attribute — RevenueCat surfaces it on the customer profile rather
        // than filing it as an arbitrary key. Sent after `logIn` on purpose: attributes attach to
        // whichever customer is current, so setting it first would put the email on the anonymous
        // id that `logIn` is about to leave behind.
        //
        // Fire-and-forget by design: the SDK queues attributes locally and flushes them with the
        // next backend call, so there is nothing to await and a failure here must never affect
        // whether someone can use the app.
        if let email = BackendService.currentUserEmail {
            Purchases.shared.attribution.setEmail(email)
        }
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
        await travel.stopFlightsRealtimeSubscription()
        // Must happen *before* `BackendService.signOut()` — unregistering relies on the
        // `device_push_tokens` "delete own" RLS policy, which needs `auth.uid()` to still resolve
        // to this account. Best-effort: a failure here just means this device keeps getting
        // pushed to until a different account signs in and reassigns the token, same as before
        // this existed — not worth blocking sign-out over.
        if let lastRegisteredPushTokenHex {
            try? await sessionTeardown.unregisterDeviceToken(lastRegisteredPushTokenHex)
        }
        // Before signing out too, for the same reason: ending a Live Activity also ends its token
        // row on the server, which needs the session. Run after it, as it used to be from
        // `clearLocalSessionState()`, every one of those calls was refused and swallowed, and the
        // server kept pushing to cards for an account no longer on the phone.
        await sessionTeardown.endLiveActivities()
        try? await sessionTeardown.signOut()
        await clearLocalSessionState()
    }

    /// Permanently deletes this account (see `BackendService.deleteAccount()`'s doc comment for
    /// exactly what that does server-side) and clears local state the same way `signOut()`
    /// does — the account is gone either way, so the device needs to end up in the same signed-
    /// out state. Rethrows so the caller (the confirmation screen) can show a real error instead
    /// of silently doing nothing if the request fails.
    ///
    /// Deletes this account only. Shared history stays with the former partner and is removed by
    /// the 90-day archive timer, which nothing here (and no client call anywhere) can bring
    /// forward — see `DeleteAccountView`'s header.
    func deleteAccount() async throws {
        await travel.stopFlightsRealtimeSubscription()
        // While the account can still end its own token rows — see `signOut()`.
        await sessionTeardown.endLiveActivities()
        try await sessionTeardown.deleteAccount()
        await clearLocalSessionState()
    }

    /// Shared by `signOut()` and `deleteAccount()` — both end with the device in the same
    /// signed-out state, whether the account still exists (just logged out of) or not (deleted).
    private func clearLocalSessionState() async {
        if Purchases.isConfigured {
            _ = try? await Purchases.shared.logOut()
        }
        PostHogSDK.shared.reset()
        // Any game answer or result still in the air belongs to the account that just left — see
        // `GameResponseOutbox.reset()`.
        sessionTeardown.resetGameResponseOutbox()
        // Without this, Home Screen widgets and Live Activities kept showing the signed-out
        // account's (and their partner's) name, photos, anniversary date, and upcoming trip/
        // flight until a different account signed in and overwrote them — none of this was
        // previously cleared by sign-out at all. (Live Activities are ended by the callers, before
        // the session goes; see `signOut()`.)
        //
        // Same reasoning as the widget snapshot below — the next account to sign in on this device
        // must not inherit this one's entitlement. (`restore(for:)` is account-scoped as a second
        // guard, but clearing on the way out is the honest place to do it.)
        Self.clearPersistedAccountState()
        WidgetCenter.shared.reloadAllTimelines()
        // Any push that already landed for the signed-out account (a trip/game update, a flight
        // alert) otherwise sat in Notification Center indefinitely, and tapping it after sign-out
        // routed into content that either no longer resolves or belongs to whoever signs in next.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        resetAccountScopedState()
    }

    /// Every store on disk or in `UserDefaults` that belongs to the signed-out account.
    ///
    /// Split out of `clearLocalSessionState()` so it can be tested, for the same reason
    /// `resetAccountScopedState()` was: the rest of that method logs out of RevenueCat and PostHog
    /// and reaches the notification centre, and `Purchases.shared` traps when it has not been
    /// configured, which it has not been in a unit test. So the disk half — the half where
    /// forgetting a store leaks one account's data to the next — was the half no test could reach.
    ///
    /// That is not hypothetical. `PendingShareStore` was added later and never added here, and
    /// nothing went red: a shared booking email survived sign-out and was offered to the next
    /// account. It is the third store to do this, after `PendingTripStore` and
    /// `PendingMemoryStore`.
    ///
    /// Adding a store to the app means adding it here. `PersistedAccountStateClearingTests` is
    /// what makes the omission fail rather than pass.
    static func clearPersistedAccountState() {
        // Same reasoning as the widget snapshot below — the next account to sign in on this device
        // must not inherit this one's entitlement. (`restore(for:)` is account-scoped as a second
        // guard, but clearing on the way out is the honest place to do it.)
        OfflineSessionCache.clear()
        OfflineDataCache.clear()
        OfflineGameStateCache.clear()
        LocalGameSessionStore.clear()
        PendingGameResponseStore.clear()
        // Every generated game's saved progress at once. One call rather than one per game, so a
        // game added later cannot leave its half-finished puzzle behind for the next account.
        PuzzleProgressCache.clearAll()
        // The catalogue itself, not just this account's view of it — the next person signing in
        // falls back to the bundled seed until their own refresh runs, rather than inheriting a
        // copy fetched under someone else's subscription tier.
        GameContentStore.clear()
        // Drafted-but-unsynced trips and memories. Neither store is scoped to a user and both are
        // restored unconditionally by `loadSignedInState`, so the next account inherited the
        // previous one's drafts — and `performAdopt` flushes those to the backend, which turned an
        // inherited draft into a write into somebody else's couple. The memory drafts carry their
        // photo bytes too.
        PendingTripStore.clear()
        PendingMemoryStore.clear()
        // Edits waiting to be sent, for the same reason: each goes out as whoever is signed in
        // when it is sent.
        PendingWriteStore.clear()
        // Written by the share extension, read by `HomeView` with no user id in the record. Holds
        // the text of a shared booking email, including anything scraped from a boarding pass.
        PendingShareStore.clear()
        clearAccountScopedDefaults()
        MemoryPhotoDiskCache.clear()
        RemoteImageDiskCache.clear()
        WidgetSnapshot.clear()
        WidgetImageCache.clearAll()
    }

    /// The two `UserDefaults` keys that belong to the account rather than to the device.
    ///
    /// `dormancy.lastTouchedOn` throttles `touchLastActive()` to one call a day. Left behind, an
    /// account signing in after another one had already touched today would skip its own stamp,
    /// and the dormancy timer reads nothing else.
    ///
    /// `streakRepairOfferedForMissedDate` records the day a repair was offered for, so a new
    /// account inherited a suppressed offer for a streak that was never theirs.
    ///
    /// Deliberately not here: `appLockEnabled`, which is a device security preference, and the
    /// `reviewPrompt.*` keys, which exist to stop pestering *the person holding the phone* — the
    /// App Store's own prompt is rate-limited per device regardless, so clearing them would only
    /// mean asking somebody who already said yes a second time.
    private static func clearAccountScopedDefaults() {
        for key in ["dormancy.lastTouchedOn", "streakRepairOfferedForMissedDate", ConnectFourSeenResults.key] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Where `finishOnboarding()` records that somebody finished when the server write did not
    /// land — see its comment for why that must not simply be dropped.
    ///
    /// Keyed by user id rather than cleared on sign-out, and the two are not the same thing. A
    /// bare key would admit the next account to sign in on this phone straight past onboarding it
    /// has never done. Keying it means the note stays true for the account it was written about,
    /// including across a sign-out and back in — which is the case that needs it most, because
    /// signing out and in is exactly what somebody does when the app will not let them in.
    static func onboardingCompletedLocallyKey(for userID: UUID) -> String {
        "onboardingCompletedLocally.\(userID.uuidString)"
    }

    /// Whether a signed-in, unpaired account should be sent through onboarding — split out from
    /// `loadSignedInState` for the same reason `resetAccountScopedState` was: it is the decision
    /// that locks somebody out of the app, and it is pure, so it can be tested without a backend.
    ///
    /// Either source saying "done" is enough. The two can only disagree when a completion write
    /// failed, and in that case the device is the one holding the newer truth.
    static func shouldRouteToOnboarding(serverSaysCompleted: Bool, completedLocally: Bool) -> Bool {
        !serverSaysCompleted && !completedLocally
    }

    private static func rememberOnboardingCompletedLocally() {
        guard let userID = BackendService.currentUserID else { return }
        UserDefaults.standard.set(true, forKey: onboardingCompletedLocallyKey(for: userID))
    }

    private static func onboardingCompletedLocally(for userID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: onboardingCompletedLocallyKey(for: userID))
    }

    private static func forgetOnboardingCompletedLocally(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: onboardingCompletedLocallyKey(for: userID))
    }

    /// Everything in memory that belongs to the signed-in account or its couple.
    ///
    /// Most of it is in the child stores, and each store's own `reset()` lists what it clears. What
    /// is left on this class is cleared here. The rule, for anything added later: if it is loaded
    /// from the account or the couple, it belongs in a store's `reset()` or here. The default for a
    /// new property used to be to be forgotten here, and the symptom was always somebody seeing
    /// another account's content — twenty-four of this class's thirty-two stored properties once
    /// survived sign-out. Only three things are deliberately kept: `isLoadingSession`, which is
    /// session lifecycle rather than account data; `accountDeletedMessage`, which is set *after*
    /// signing out in order to explain why; and `refreshAllCount`, a test probe.
    ///
    /// Separate from `clearLocalSessionState()` so it can be tested: that method logs out of
    /// RevenueCat, PostHog and the notification centre, and `Purchases.shared` traps when it has
    /// not been configured — which it has not been, in a unit test.
    func resetAccountScopedState() {
        accountGeneration += 1
        lastRegisteredPushTokenHex = nil
        for store in accountScopedStores { store.reset() }

        // The reported leak. These are *signed Storage URLs*, so leaving them is worse than a
        // stale cache: the next account's Home fetched and drew the previous couple's drawing over
        // the network, from a URL that is still valid. The thumbnail was theirs; opening the pad
        // showed the new account's own (empty) one, which is the mismatch that made it visible.
        myDrawingURL = nil
        partnerDrawingURL = nil
    }

    /// Persists profile edits from `SettingsView`. Each field only round-trips to the backend
    /// if it actually changed, since `updateFirstName`/`updateHomeCity` are separate writes.
    func updateProfile(name: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != session.couple.partnerA.name {
            let previous = session.couple.partnerA.name
            await commit(.firstName(trimmedName)) {
                session.couple.partnerA.name = previous
                writeRefusedMessage = Self.profileRefusedMessage
            }
        }
    }

    private static let profileRefusedMessage = "That change wasn't saved."

    func updateAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadAvatar(imageData: imageData)
        AvatarView.preloadCache(imageData: imageData, url: url)
        session.couple.partnerA.avatarURL = url
    }

    /// Always editable, paired or not — this is *your own, personal* name for your partner
    /// (a nickname, a pet name, whatever you call them), never their real account data. Your
    /// partner has their own independent nickname for you, if they've set one; neither side
    /// overwrites the other's. See `BackendService.updatePartnerNickname`.
    func updatePartnerName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != session.couple.partnerB.name else { return }
        let previous = session.couple.partnerB.name
        await commit(.partnerNickname(trimmed)) {
            session.couple.partnerB.name = previous
            writeRefusedMessage = Self.profileRefusedMessage
        }
    }

    /// Unlike the name (always personal), the city is shared/real once paired — only
    /// meaningful to set here before that, as a personalization guess. `SettingsView` disables
    /// this field once `partnerConnected` is true.
    func updatePartnerHomeCity(_ city: Place) async {
        guard city.id != session.couple.partnerB.homeCity?.id else { return }
        let previous = session.couple.partnerB.homeCity
        await commit(.partnerHomeCity(city)) {
            session.couple.partnerB.homeCity = previous
            writeRefusedMessage = Self.profileRefusedMessage
        }
    }

    /// Always personal, paired or not — it's always *your own* custom photo of your partner,
    /// independent of whatever avatar they picked for themselves (see
    /// `BackendService.uploadPartnerAvatar`).
    func updatePartnerAvatar(imageData: Data) async throws {
        let url = try await BackendService.uploadPartnerAvatar(imageData: imageData)
        AvatarView.preloadCache(imageData: imageData, url: url)
        session.couple.partnerB.avatarURL = url
    }

    /// Once paired, `couples.started_dating_on` is the value re-fetches actually read back
    /// (`profiles.anniversary_date` only matters pre-pairing), so this must target whichever one
    /// is actually authoritative right now or the edit silently reverts on the next refresh.
    func updateAnniversaryDate(_ date: Date) async {
        guard date != session.couple.startedDatingOn else { return }
        let previous = session.couple.startedDatingOn
        // Which of the two it lands on is decided when it is sent — see `deliver`.
        await commit(.anniversaryDate(date)) {
            session.couple.startedDatingOn = previous
            writeRefusedMessage = Self.profileRefusedMessage
        }
    }

    /// Sets or clears this person's own birthday. Nil removes it, which is always allowed — it is
    /// optional wherever it is asked for, including onboarding.
    ///
    /// Only ever `partnerA`, who is always me. There is no partner equivalent on purpose: a
    /// birthday belongs to the person whose it is, and the partner's arrives with their profile
    /// (see `BackendService.fetchCoupleState`). Letting each side record a guess at the other's
    /// would give the reminder two dates and no way to choose.
    ///
    /// Applied locally after the write rather than before, so a failure leaves the screen showing
    /// what is actually stored.
    func updateBirthday(_ birthday: Birthday?) async {
        guard birthday != session.couple.partnerA.birthday else { return }
        do {
            try await BackendService.updateBirthday(birthday)
            session.couple.partnerA.birthday = birthday
        } catch {
            writeRefusedMessage = BackendFailure.message(for: error)
        }
    }




    /// Accepts or declines an incoming request. On accept, re-checks couple state immediately
    /// rather than waiting for the next foreground/background refresh — the whole point of
    /// accepting right now is to connect right now. Returns an error message on failure, nil on
    /// success (same shape as `removePartner()`).
    @discardableResult
    func respondToConnectionRequest(
        _ request: BackendService.PendingConnectionRequest,
        accept: Bool,
        restoreArchive: Bool = false
    ) async -> String? {
        do {
            let coupleID = try await BackendService.respondToConnectionRequest(
                id: request.id, accept: accept, restoreArchive: restoreArchive
            )
            session.pendingConnectionRequests.removeAll { $0.id == request.id }
            if coupleID != nil {
                await refreshCoupleStateIfNeeded()
            }
            return nil
        } catch {
            return BackendFailure.message(for: error)
        }
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
            return BackendFailure.message(for: error)
        }
        Analytics.capture(Analytics.Event.partnerRemove)
        await settleAfterLeavingCouple()
        return nil
    }

    /// Ends the partnership and blocks them, in one step: `block_profile` disconnects first when
    /// the person blocked is the current partner (20261023000000). Then settles exactly as
    /// `removePartner()` does. The block button used to call the RPC and close the screen without
    /// this, so the app went on showing the partner as connected until a pull-to-refresh reloaded
    /// it. Returns nil on success, or a message saying what went wrong.
    func blockPartner() async -> String? {
        guard backendCoupleID != nil else { return "No partner to block." }
        // Taken now: settling below replaces `partner` with the empty solo placeholder.
        let blocked = ReportedPersonContext(profileID: partner.id, displayName: partner.name, surface: .partner)
        do {
            try await BackendService.blockProfile(blocked.profileID)
        } catch {
            return "Couldn't block them. Please try again."
        }
        Analytics.capture(Analytics.Event.partnerRemove)
        // Not awaited: support hearing about it is not something the person blocking should wait on.
        Task { await HelpService.notifyBlock(of: blocked) }
        await settleAfterLeavingCouple()
        return nil
    }

    /// What follows the couple ending, however it ended.
    private func settleAfterLeavingCouple() async {
        // The old code is now permanently invalid server-side (`redeem_invite_code` rejects a
        // non-"pending" code) — without clearing it, `PartnerConnectCard`'s `if inviteCode ==
        // nil` guard would reshare this same dead code to whoever the user invites next, and
        // their redemption attempt would fail with no obvious reason why.
        session.inviteCode = nil
        await loadSignedInState()
        // HomeView's setup checklist card (the "invite your partner" hint) remembers a past
        // dismissal forever, server-side — without resetting it, someone who'd already
        // dismissed it once (e.g. during their original onboarding) would see no hint at all
        // here, even though they're now genuinely back in the same unpaired state a brand-new
        // user starts in and need that same nudge again.
        prompts.setupChecklistDismissed = false
        Task { await BackendService.resetSetupChecklistDismissed() }
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
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard session.hasCouple else { return }
        // Taken before the fetch: an answer about the account that has since signed out must not
        // be adopted for whoever is signed in now (or for nobody).
        let generation = accountGeneration
        switch await fetchCoupleStateOutcome() {
        case let .paired(state):
            await adopt(state, startedIn: generation)
        case .noCouple:
            // The backend answered, and there is no active couple. This is the only outcome that
            // may tear down a pairing — see `CoupleStateOutcome` for the Wi-Fi blip that used to
            // reach here and announce that the partner had disconnected.
            guard isCurrent(generation) else { return }
            if session.partnerConnected, let profile = try? await BackendService.fetchOwnProfile() {
                await adoptSoloProfile(profile, startedIn: generation)
            } else {
                // Still solo, so this is the foreground or reconnect that would have replayed the
                // outbox through `performAdopt` for a couple.
                await syncPendingWrites()
            }
        case .unknown:
            break
        }
    }

    /// Drawing pad paths are fully deterministic (`{coupleID}/{personID}/pad.png`), so unlike
    /// trips/memories there's nothing to "fetch" beyond just pointing at a URL — this just primes
    /// both URLs so the pad previews have something to render on first appearance.
    ///
    /// `drawing-pads` is a private bucket now (see `BackendService.drawingPadSignedURL`'s doc
    /// comment), so this needs a real signed-URL round trip rather than just building a public
    /// URL string — and since each signed URL embeds its own unique token, it's never the same
    /// string twice, which is what used to require the separate manual cache-busting step here
    /// (re-fired from `DrawingPadCard.onAppear` on top of whatever `saveMyDrawing` just set).
    ///
    /// `sign` is the signing round trip, passed in so a failed one can be tested without a network.
    func loadDrawingPads(
        sign: (UUID, UUID) async throws -> URL = BackendService.drawingPadSignedURL(coupleID:personID:)
    ) async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard let backendCoupleID else { return }
        // Signed URLs, so landing after sign-out would hand the previous couple's drawings to the
        // next account's Home — the leak `resetAccountScopedState` describes.
        let generation = accountGeneration
        let personIDs = (mine: currentUser.id, theirs: partner.id)
        // Only a URL that was actually signed replaces the one held (HOME-9). Signing is a network
        // round trip, so offline — or on any passing failure, and this runs on every refresh —
        // `try?` used to assign nil, and both pads went blank while their drawings sat in
        // `RemoteImageDiskCache` under a path nothing could look up any more.
        let mine = try? await sign(backendCoupleID, personIDs.mine)
        guard isCurrent(generation) else { return }
        if let mine { myDrawingURL = mine }
        let theirs = try? await sign(backendCoupleID, personIDs.theirs)
        guard isCurrent(generation) else { return }
        if let theirs { partnerDrawingURL = theirs }
    }

    /// Fires once — the first time a couple both (a) has a connected partner and (b) has already
    /// done something with the app (a trip, memory, or tracked flight). Deliberately not keyed to
    /// any one of those in isolation — the couple isn't "connected" yet during onboarding
    /// (`hasCouple` only flips true at the very end), so this can never fire mid-onboarding, and
    /// asking right after a still-solo first action reads as premature. "First game results" isn't
    /// state AppModel tracks directly, so that one's raised via `noteReviewMilestone(_:)` from
    /// `GameResultsView` instead.
    func checkReviewMilestones() {
        guard session.hasCouple, session.partnerConnected else { return }
        guard !travel.trips.isEmpty || !travel.memories.isEmpty || !travel.flights.isEmpty else { return }
        prompts.notePartnerConnectedMilestone()
    }

    /// Call after a solo (unpaired) user finishes adding a trip/memory or completes a game —
    /// surfaces `PartnerInviteNudgeView` at most once a day. No-ops once paired (nothing left to
    /// invite anyone to) or while a request is already pending (they've already invited someone —
    /// Home's own pending-invite card, not this nudge, is the right prompt for that state).
    func noteSoloActionCompleted() {
        guard !session.partnerConnected, session.pendingOutgoingConnectionRequest == nil else { return }
        prompts.noteSoloActionCompleted()
    }

    // MARK: - Games: Daily Activity + topic browsing

    #if DEBUG
    /// How many times `refreshAll()` has been entered. Exists so a UI test can prove the
    /// pull-to-refresh gesture is actually wired up, which cannot be done by looking for the
    /// spinner: XCUITest quiesces the app before every accessibility query, so a refresh that
    /// completes in under a second has always finished (and its control disappeared) by the time
    /// any query can observe it. A counter survives that; a transient view does not.
    /// See `PullToRefreshUITests`. DEBUG-only, so it can't exist in a shipped build.
    var refreshAllCount = 0
    #endif

    /// Everything a pull-to-refresh should pull. Every tab shares this rather than each one
    /// re-listing the subset it happens to display: what a person means by pulling down is "get
    /// me current", and being told that only Travel refreshes trips is not a distinction worth
    /// making them learn. It's user-initiated and infrequent, so the extra breadth is affordable
    /// in a way the automatic on-appear refreshes aren't.
    ///
    /// Unconditional by design — the `…IfNeeded` variants exist to keep automatic refreshes cheap,
    /// and reusing them here would make the gesture do nothing precisely when someone reaches for
    /// it because the screen looks stale.
    func refreshAll() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        #if DEBUG
        refreshAllCount += 1
        #endif
        // The only "…IfNeeded" that stays: its guard is `hasCouple`, not a staleness check, so
        // it already re-fetches every time it's called.
        //
        // And the only one of the travel refreshes needed. For a couple, `fetchCoupleState`
        // already returns trips, flights and memories — so pairing it with `refreshTrips`/
        // `refreshFlights`/`refreshMemories` fetched all three twice per pull, and signed every
        // photo the couple has ever added a second time along with them. Without a couple there is
        // nothing for them to fetch: each returns at once on a nil `backendCoupleID`, which is
        // every case where `hasCouple` is false (a solo account has `hasCouple` true and no couple
        // id). They used to be called here for `!hasCouple` anyway, three no-ops.
        async let coupleState: Void = refreshCoupleStateIfNeeded()
        async let decks: Void = games.refreshGameDecks()
        async let streak: Void = games.refreshDailyStreak()
        async let pads: Void = loadDrawingPads()
        _ = await (coupleState, decks, streak, pads)
        if needsPartnerInvite {
            await session.refreshPendingConnectionRequests()
        }
    }

    /// Only available once paired — there's no couple to namespace the storage path under
    /// beforehand, and no partner pad to make the feature meaningful yet.
    ///
    /// Returns whether the drawing reached the server, so the editor can stay open with the strokes
    /// still on it when it didn't.
    func saveMyDrawing(imageData: Data) async -> Bool {
        // -demoMode: nothing is saved, and the editor closes as it always has rather than
        // reporting a failure in the middle of a screenshot run.
        if DemoMode.isOn { return true }
        guard let backendCoupleID else { return false }
        let personID = currentUser.id
        return await commitMyDrawing(imageData: imageData) {
            try await BackendService.uploadDrawingPad(coupleID: backendCoupleID, personID: personID, imageData: $0)
        }
    }

    /// `saveMyDrawing` after the couple check, with the upload passed in so a failed one can be
    /// tested without a network.
    ///
    /// A failure leaves `myDrawingURL` alone. This used to assign the upload's `try?` result
    /// unconditionally, so a failed save set it to `nil`: Home showed the pad as empty, and the
    /// next editor session had no URL to load from, opened blank, and on save overwrote the real
    /// drawing on the server with whatever was drawn in it.
    func commitMyDrawing(imageData: Data, upload: (Data) async throws -> URL) async -> Bool {
        guard let uploadedURL = try? await upload(imageData) else { return false }
        // We already hold the bytes that were just uploaded, so put them in the disk cache
        // rather than making the next reader download what we just sent. This also keeps the
        // offline copy correct: without it, a save followed by going offline would show the
        // *previous* drawing back again, since that is what was still cached under this path.
        RemoteImageDiskCache.store(imageData, for: uploadedURL)
        myDrawingURL = uploadedURL
        Analytics.capture(Analytics.Event.doodleSave)
        Task { await BackendService.notifyPartner(event: .drawingSaved) }
        // The pad is saved over the same storage path, so nothing in the snapshot changes: name
        // the drawing pad widget, or it shows the old drawing until its own half-hourly reload.
        Task { await WidgetSnapshotWriter.refresh(appModel: self, alsoReload: [.drawingPad]) }
        return true
    }

    /// Serializing entry point — see `inFlightAdopt`'s doc comment for why this can't just be
    /// the function body directly. Each adopt waits for its predecessor, then runs.
    ///
    /// Chained rather than spun on. This used to be
    ///
    ///     while let inFlight = inFlightAdopt { await inFlight.value }
    ///
    /// which livelocks whenever two adopts overlap: the second reads the flag before the first has
    /// cleared it, awaits a task that has *already* finished, returns immediately, loops, and reads
    /// the same finished task again. On the main actor that is a spin, and the app sits on the
    /// splash screen forever — `restoreSession`'s `defer` never runs, so `isLoadingSession` never
    /// clears. Sampled in that state: 187 of 187 main-thread samples inside this loop.
    ///
    /// Two adopts overlap easily — `loadSignedInState` at launch and `refreshCoupleStateIfNeeded`
    /// on foreground both reach here — and the window is however long `performAdopt` takes.
    ///
    /// Holding the tail of a chain removes the loop entirely: waiting happens inside the new task,
    /// so there is no flag to re-read and nothing to clear. `inFlightAdopt` is only ever the most
    /// recently queued adopt, and each one releases its predecessor as it completes.
    ///
    /// `generation` is `accountGeneration` as it was before `state` was fetched. Sign-out moves it
    /// on, and an adopt that finds it has moved does nothing more: a fetch that left before
    /// somebody signed out and came back after it used to put the previous couple back on screen,
    /// restart their flights channel and write their data into the offline cache for nobody.
    private func adopt(_ state: BackendService.CoupleState, startedIn generation: Int) async {
        let previous = inFlightAdopt
        let task = Task { [weak self] () -> Void in
            await previous?.value
            await self?.performAdopt(state, startedIn: generation)
        }
        inFlightAdopt = task
        await task.value
    }

    /// Adopts real couple/trip/memory rows from the backend, flushing anything that was added
    /// locally before pairing completed (drafted during onboarding, or via the home screen's
    /// "add a trip"/"add a memory" cards while still solo).
    private func performAdopt(_ state: BackendService.CoupleState, startedIn generation: Int) async {
        // Checked again after every suspension below, for the same reason.
        guard isCurrent(generation) else { return }
        // The retry list below is built from what is on screen, so anything a refresh or a reset
        // took off the screen would also stop being retried — for the rest of the session, until a
        // relaunch read it back from disk. Reading it back here as well means the disk copy, not
        // the array, decides what is still waiting.
        travel.restorePendingMemoriesFromDisk()
        travel.restorePendingTripsFromDisk()
        let localOnlyTrips = travel.trips.filter { travel.pendingTripIDs.contains($0.id) }
        let localOnlyMemories = travel.memories.filter { travel.pendingMemoryIDs.contains($0.id) }

        session.couple = state.couple
        session.backendCoupleID = state.couple.id
        travel.trips = state.trips
        travel.memories = state.memories
        travel.flights = state.flights
        // These three assignments replace the arrays wholesale, so an optimistic edit made while
        // the fetch was in the air is overwritten by the server's older copy. `refreshTrips`,
        // `refreshFlights` and `refreshMemories` have always reapplied here; this one never did,
        // and `refreshAll` only got away with it because it called those three afterwards and
        // they reapplied on its behalf. It no longer does — see `refreshAll`.
        reapplyPendingWrites()
        Task { [weak self] in await self?.travel.resolveMissingAirportTimezones() }
        // Both of these used to be assigned ~50 lines below, after the `await` on the next
        // subscription line. `partnerConnected` flipping true is what `RootView` watches to show
        // the "You're connected!" celebration, and its guard is `partnerConnectedCelebrationShown`
        // — which, across that suspension point, was still the `false` it defaults to. SwiftUI got
        // a render in between, so the celebration fired on every single sign-in of an
        // already-paired couple, and then wrote `true` to a server flag that the next launch's
        // fresh AppModel would once again not have read yet.
        //
        // They come straight out of `state`, which has been in hand since the top of this
        // function, so there was never a reason to set them late. Ordering is the whole fix: no
        // suspension point may sit between a flag being false-by-default and the value that
        // corrects it. Same shape as the subscription card that flashed on Home.
        prompts.partnerConnectedCelebrationShown = state.partnerConnectedCelebrationShown
        prompts.setupChecklistDismissed = state.setupChecklistDismissed
        session.partnerConnected = true
        session.hasCouple = true
        // Reconnecting makes the notice obsolete. It is set by `adoptSoloProfile` when a partner
        // leaves and was only ever cleared by the alert being dismissed, so re-pairing — with the
        // same person or a new one — left "your connection with X has ended" sitting over a Home
        // screen that was showing the new couple.
        prompts.partnerDisconnectedMessage = nil
        let subscribed = await subscription.resolvedActive(backendSaysActive: state.subscriptionActive)
        // ORed with the device, because the row can lag a purchase made moments ago — and a buyer
        // who is told nothing about cancelling is the worse of the two mistakes.
        let deviceEntitled = await subscription.deviceHoldsEntitlement()
        guard isCurrent(generation) else { return }
        subscription.apply(
            active: subscribed,
            viewerHolds: state.viewerSubscriptionActive || deviceEntitled,
            tier: state.subscriptionTier,
            viewerStore: state.viewerSubscriptionStore
        )
        session.hasLoadedCoupleState = true
        // The backend has just told us the couple-wide truth — remember it so a later cold launch
        // with no network doesn't fall back to `false` and paywall a real subscriber.
        OfflineSessionCache.record(
            active: state.subscriptionActive,
            tier: state.subscriptionTier,
            userID: BackendService.currentUserID,
            partnerConnected: true,
            myName: state.couple.partnerA.name,
            partnerName: state.couple.partnerB.name,
            celebrationShown: state.partnerConnectedCelebrationShown,
            checklistDismissed: state.setupChecklistDismissed
        )
        OfflineDataCache.record(
            trips: state.trips,
            flights: state.flights,
            memories: state.memories,
            myCity: state.couple.partnerA.homeCity,
            partnerCity: state.couple.partnerB.homeCity,
            myAvatarURL: state.couple.partnerA.avatarURL,
            partnerAvatarURL: state.couple.partnerB.avatarURL,
            myDrawingURL: myDrawingURL,
            partnerDrawingURL: partnerDrawingURL,
            couple: state.couple,
            userID: BackendService.currentUserID
        )
        travel.prefetchMemoryPhotos()
        // Adoption is the only thing that sets `backendCoupleID`, and the drawing pads are the one
        // part of Home whose contents it does *not* hand over — trips, memories and flights all
        // arrive in `state`, so they survive being fetched too early; the pads are two signed URLs
        // that have to be asked for separately, behind a `guard let backendCoupleID`. Every caller
        // raced that guard: `refreshAll` starts `loadDrawingPads()` with `async let` alongside the
        // couple fetch that sets the ID, and both `.task` sites fire when their view appears. A
        // loss is permanent, because nothing re-runs it — so the pads stayed blank for the whole
        // session. Kicking it off here means the fetch happens *because* the ID now exists.
        //
        // NOT awaited. The ID it needs is already set, so a detached task sees it — and awaiting
        // put two signed-URL round trips on the launch path, inside the adopt that everything else
        // serializes behind. Nothing on screen waits for a pad URL; the splash screen was waiting
        // for both of them.
        Task { [weak self] in await self?.loadDrawingPads() }
        noteCurrentDistanceIfRecord()

        // Created now, the drafts made before there was a couple to create them in.
        guard await travel.flushLocalOnly(trips: localOnlyTrips, memories: localOnlyMemories, into: state.couple, startedIn: generation) else { return }
        // Again now the pending trips and memories are back in the arrays, for an edit made to one.
        reapplyPendingWrites()
        // Edits go after creates, so one made to a trip or memory just created above can now be
        // sent. Not awaited: a queue of photos is no reason to hold up everything waiting on adopt.
        Task { [weak self] in await self?.syncPendingWrites() }
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
        await travel.startFlightsRealtimeSubscription(coupleID: state.couple.id)
    }

    /// Opportunistic persistence for the Stats tab's "Longest distance between" milestone — fires
    /// every time fresh couple state loads (this runs from `performAdopt`, itself called on every
    /// foreground refresh), which is exactly when both partners' home cities are known to be
    /// current. Only calls the backend when today's distance would actually raise the stored
    /// record, both to avoid a pointless network call on every refresh and because the RPC's own
    /// `GREATEST` is a safety net for races, not something to lean on for the common case.
    private func noteCurrentDistanceIfRecord() {
        guard let mine = session.couple.partnerA.homeCity?.coordinate, let theirs = session.couple.partnerB.homeCity?.coordinate else { return }
        let currentKm = Geo.distanceKm(mine, theirs)
        guard currentKm > (session.couple.maxDistanceKm ?? 0) else { return }
        let coupleID = session.couple.id
        Task { try? await BackendService.updateCoupleMaxDistance(coupleID: coupleID, distanceKm: currentKm) }
    }

    /// Called once account creation succeeds — now happens *before* the paywall/trial screens
    /// rather than after, so a real account exists to tie the subscription to. Persists
    /// everything collected during the default onboarding flow (situation/frequency/
    /// attribution/goals go to PostHog as person properties via `Analytics.setOnboardingTraits`,
    /// not Supabase — they're analytics-segmentation traits, not app data anything else reads;
    /// names/cities/photos/drafted flight apply here) — nothing could be written to Supabase
    /// before a session existed. Deliberately does **not** set `hasCouple = true`: `RootView` swaps
    /// straight to `MainTabView` the instant that flips, which would skip the paywall/trial
    /// screens still left to show. `finishOnboarding()` does that final flip once they're done.
    ///
    /// If a real couple already exists (the partner redeemed an invite in a race, or this is
    /// the preserved deep-link path resuming a session that already finished pairing), there's
    /// nothing left to onboard, so this does finish immediately — a narrow edge case where a
    /// returning user skips straight past the paywall.
    func applyOnboardingAccount(_ onboarding: OnboardingModel) async {
        // One at a time. Each screen that calls this is a button, and a second tap used to run all
        // of it again — the photos uploaded twice, every answer written twice. A tap while it is
        // running waits for that run instead of starting its own.
        if let inFlightApply {
            await inFlightApply.value
            return
        }
        let task = Task { await performApplyOnboardingAccount(onboarding) }
        inFlightApply = task
        await task.value
        inFlightApply = nil
    }

    /// The run `applyOnboardingAccount` and `finishOnboarding` wait on, if one is going.
    private var inFlightApply: Task<Void, Never>?
    private var inFlightFinish: Task<Void, Never>?

    /// Records that onboarding has made this account, so a relaunch offers to resume rather than
    /// starting again at question one. See `hasSavedOnboardingProgress`.
    func recordOnboardingAccountCreated() async {
        // Set locally as well as remotely, and not only as an optimisation: nothing re-reads
        // the profile between here and the end of the flow, so without this the flag would be
        // false for the rest of this session.
        session.hasSavedOnboardingProgress = true
        do {
            try await BackendService.markOnboardingAccountCreated()
        } catch {
            // Nothing to undo and nothing worth interrupting a signup for. The cost is that a
            // dropout is restarted rather than resumed, which is where they were before this
            // column existed.
            print("[AppModel] could not record onboarding account creation: \(error.localizedDescription)")
        }
    }

    private func performApplyOnboardingAccount(_ onboarding: OnboardingModel) async {
        let generation = accountGeneration
        if case let .paired(state) = await fetchCoupleStateOutcome() {
            guard isCurrent(generation) else { return }
            await adopt(state, startedIn: generation)
            guard isCurrent(generation) else { return }
            session.inviteCode = onboarding.inviteCode
            session.hasCouple = true
            return
        }

        if let userID = BackendService.currentUserID {
            adoptSignedInIdentity(id: userID, firstName: onboarding.firstName)
            // Before anything else, because the onboarding paywall is four screens away and
            // `Purchases.shared` is still on its anonymous id until this runs.
            //
            // `identifyWithRevenueCat()` used to be called from `loadSignedInState()` alone —
            // launch, manual sign-in, and un-pairing. None of those happen between an account
            // being created here and that paywall, so a first purchase attached to
            // `$RCAnonymousID:…` rather than to the Supabase user. The buyer saw their
            // subscription (the SDK holds the entitlement locally) and the server never learned
            // of it: the webhook's event carried no resolvable Supabase id, and
            // `sync-my-subscription` asked RevenueCat about a UUID it had nothing under. So
            // `subscription_active` stayed false with `subscription_checked_at` null — which is
            // also why the partner, who has only the row to go on, was told there was no
            // subscription at all.
            await identifyWithRevenueCat()
            // The boundary this records is exactly here: an account now exists, and everything the
            // questionnaire collected is about to be written to it a few lines below. Anyone who
            // stops between this point and `finishOnboarding()` is the person the resume screen is
            // for — which is a likely place to stop, since the paywall three screens later cannot
            // be dismissed.
            await recordOnboardingAccountCreated()
            // The device's push token typically arrives at launch, well before this signup
            // completes and `currentUserID` becomes valid — `registerPushToken` would have
            // silently cached it rather than dropped it (see `pendingPushTokenData`'s own doc
            // comment), but nothing flushed that cache for a fresh signup completed in one
            // continuous onboarding session (no relaunch, no `SignInView`). Without this, that
            // device never gets a `device_push_tokens` row until the next cold launch.
            await retryPendingPushTokenRegistrationIfNeeded()
            Analytics.setOnboardingTraits(
                userID: userID,
                attribution: onboarding.attribution,
                situation: onboarding.situation,
                frequency: onboarding.frequency,
                goals: onboarding.goals,
                userGender: onboarding.userGender,
                partnerGender: onboarding.partnerGender
            )
        }

        if let selfPhotoData = onboarding.selfPhotoData,
           let url = try? await BackendService.uploadAvatar(imageData: selfPhotoData) {
            AvatarView.preloadCache(imageData: selfPhotoData, url: url)
            session.couple.partnerA.avatarURL = url
        }
        if let partnerPhotoData = onboarding.partnerPhotoData,
           let url = try? await BackendService.uploadPartnerAvatar(imageData: partnerPhotoData) {
            AvatarView.preloadCache(imageData: partnerPhotoData, url: url)
            session.couple.partnerB.avatarURL = url
        }

        // `signUp` carries first_name in the user metadata that `handle_new_user` reads, so the
        // email path persisted it and this write looks redundant. It is not: the Apple and Google
        // buttons never call `signUp`, they land straight here, so every account that onboarded
        // with SSO had its name collected by `YourNameView`, shown back to it all the way through
        // the flow, and then dropped — `profiles.first_name` stayed '' and the next sign-in read
        // it back as "You". Idempotent for the email path, which is writing the same string it
        // already sent.
        //
        // These go through the outbox like any other edit, so an answer given on a dropped
        // connection is sent later rather than lost. None is refusable by the subscription.
        if !onboarding.firstName.isEmpty {
            await commit(.firstName(onboarding.firstName)) {}
        }

        if let homeCity = onboarding.homeCity {
            await commit(.homeCity(homeCity)) {}
        }

        if !onboarding.partnerName.isEmpty {
            await commit(.partnerNickname(onboarding.partnerName)) {}
        }
        if let partnerCity = onboarding.partnerCity {
            await commit(.partnerHomeCity(partnerCity)) {}
        }

        if let anniversaryDate = onboarding.anniversaryDate {
            await commit(.anniversaryDate(anniversaryDate)) {}
        }

        // Only when they gave one. `BirthdayView` has a Skip, and skipping leaves this nil — which
        // must stay nil rather than being written as some default, both because there is no
        // sensible default for a birthday and because the column pair is all-or-nothing.
        if let birthday = onboarding.birthday {
            try? await BackendService.updateBirthday(birthday)
            session.couple.partnerA.birthday = birthday
        }

        session.inviteCode = onboarding.inviteCode
    }

    /// The actual last step of onboarding — called once the paywall/trial flow finishes, so
    /// `RootView` lands the user in `MainTabView`. Account creation already happened earlier
    /// via `applyOnboardingAccount`.
    ///
    /// Does the same post-admission work `loadSignedInState` does after its own `hasCouple = true`,
    /// and for the reason that function already gives: everything gated on `hasCouple` is resolved
    /// by whichever path admits somebody, because the things that would otherwise resolve them run
    /// from a `.task` that has already fired. During onboarding `hasCouple` is false, so
    /// `RootView`'s launch task returns early from
    /// `refreshPendingOutgoingConnectionRequestIfNeeded`, and nothing re-runs it — leaving
    /// `hasResolvedOutgoingConnectionRequest` false and Home with no "Set up your partner" card at
    /// all until something unrelated happened to trigger a refresh. That was the ten-second gap on
    /// a freshly created account: not a slow lookup, a lookup nobody had asked for yet.
    ///
    /// Awaited before the flip rather than after, so Home's first render already knows. Somebody
    /// finishing onboarding usually has no partner and no outgoing request, so this is one quick
    /// round trip — plus the couple fetch below, for the inviter whose partner did not wait.
    func finishOnboarding() async {
        // One at a time, for the reason `applyOnboardingAccount` gives.
        if let inFlightFinish {
            await inFlightFinish.value
            return
        }
        let task = Task { await performFinishOnboarding() }
        inFlightFinish = task
        await task.value
        inFlightFinish = nil
    }

    private func performFinishOnboarding() async {
        let generation = accountGeneration
        // Recorded server-side, because this is the write that stops the next launch routing
        // straight back into onboarding.
        //
        // It used to be a bare `try?`, on the reasoning that the account is set up either way and
        // the cost of failing is "one more trip through the flow next launch". That reasoning was
        // wrong twice over. `markOnboardingCompleted`'s own doc comment says this is the one write
        // in the flow that must not be swallowed without the caller knowing. And the screen it
        // degrades to is the first onboarding question presented as a stack root — no back button,
        // and until now no other way off it — so "one more trip through the flow" was really "no
        // way into the app until you complete onboarding again", on every launch, with a session
        // that survives reinstalling the app because it lives in the Keychain.
        //
        // So a failure is remembered on this device instead. `loadSignedInState` treats the local
        // note as good enough to admit them, and retries the write. Keyed by user id so it cannot
        // admit the *next* account to sign in on this phone.
        do {
            try await BackendService.markOnboardingCompleted()
        } catch {
            Self.rememberOnboardingCompletedLocally()
        }
        // Asked, not assumed. This used to say "nothing to fetch: this account was just built, so
        // its state is known and empty" — but an inviter shares their link at "Invite your
        // partner" and then spends three screens on the trial and the paywall, and a tapped link
        // connects the moment the partner redeems it. Nothing polls while onboarding is up, so
        // Home opened as an unpaired account with a "Set up your partner" card, beside a partner
        // who was already connected, until the next foreground refresh.
        //
        // Only a couple that really exists is adopted. `.noCouple` and `.unknown` both leave the
        // fresh account as it is, which is what it almost always is.
        if case let .paired(state) = await fetchCoupleStateOutcome() {
            guard isCurrent(generation) else { return }
            await adopt(state, startedIn: generation)
        }
        guard isCurrent(generation) else { return }
        if let userID = BackendService.currentUserID { OnboardingResume.clear(for: userID) }
        session.needsOnboarding = false
        // Known either way now: adopted above, or asked and found empty. Saying so is what lets
        // Home show the setup checklist immediately rather than a round trip later.
        session.hasLoadedCoupleState = true
        await session.refreshPendingOutgoingConnectionRequest()
        session.hasCouple = true
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }

    /// Registers this device's APNs token against the signed-in profile so
    /// `send-flight-notification` (server-side) has somewhere to deliver to. Safe to call
    /// repeatedly — the backend upserts on the token itself.
    /// Cached raw APNs token bytes, kept around until a registration attempt actually succeeds.
    /// `didRegisterForRemoteNotificationsWithDeviceToken` can fire before `restoreSession()`'s
    /// async `supabase.auth.session` restore has finished — `BackendService.registerDeviceToken`
    /// requires `currentUserID`, so a registration attempt that loses that race throws
    /// `.notAuthenticated` and (since the call site swallows it with `try?`) silently drops the
    /// token for the rest of that launch, with nothing anywhere to indicate it happened. Real
    /// symptom this caused: a signed-in couple with notifications genuinely enabled on-device,
    /// backend sends reporting success, and zero pushes ever arriving — the row in
    /// `device_push_tokens` was simply stale or missing. `loadSignedInState()` retries this once
    /// a session is confirmed, closing the race regardless of which order the two async events
    /// actually finish in.
    private var pendingPushTokenData: Data?

    /// The hex token last successfully registered — kept around purely so `signOut()` has
    /// something to unregister (see `BackendService.unregisterDeviceToken`'s own doc comment).
    /// `pendingPushTokenData` isn't a substitute for this: it's cleared to `nil` the moment
    /// registration succeeds, which is exactly when this needs to start holding a value.
    private var lastRegisteredPushTokenHex: String?

    func registerPushToken(_ tokenData: Data) async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        pendingPushTokenData = tokenData
        await retryPendingPushTokenRegistrationIfNeeded()
    }

    func retryPendingPushTokenRegistrationIfNeeded() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard let tokenData = pendingPushTokenData else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await BackendService.registerDeviceToken(token, environment: environment)
            pendingPushTokenData = nil
            lastRegisteredPushTokenHex = token
        } catch {
            // Most likely still not authenticated yet — leave it cached so the next
            // `loadSignedInState()` (or another `registerPushToken` call) can retry.
        }
    }

    /// Only ever writes the signed-in user's own city — RLS blocks updating a partner's
    /// profile row, so there's no "set it on their behalf" path anymore.
    func setHomeCity(for personID: Person.ID, city: Place) async {
        guard personID == currentUser.id else { return }
        let previous = session.couple.partnerA.homeCity
        await commit(.homeCity(city)) {
            session.couple.partnerA.homeCity = previous
            writeRefusedMessage = Self.profileRefusedMessage
        }
    }

    /// `RootView`'s foreground-triggered current-city refresh lands here once
    /// `HomeLocationService` resolves a fresh fix — compares by city/country name, not
    /// `Place.id`, since a new location fix builds a brand new `Place` (fresh random id) on
    /// every call even when the resolved city hasn't actually changed, and an id comparison
    /// would rewrite the backend row (and spuriously invalidate `HomeView`'s per-city-id weather
    /// cache) on every single foreground for no reason.
    func updateCurrentCityIfChanged(_ place: Place) async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard place.city != session.couple.partnerA.homeCity?.city || place.country != session.couple.partnerA.homeCity?.country else { return }
        await setHomeCity(for: currentUser.id, city: place)
    }

    /// Sets the signed-in user's identity as soon as an account exists, so any trip drafted
    /// during the rest of onboarding (before pairing) carries the real profile id rather
    /// than a throwaway placeholder.
    func adoptSignedInIdentity(id: UUID, firstName: String) {
        session.couple.partnerA = Person(
            id: id,
            name: firstName.isEmpty ? "You" : firstName,
            homeCity: session.couple.partnerA.homeCity,
            accentColor: Person.palette[1]
        )
    }
}

#if DEBUG
extension AppModel {
    /// Puts the model in the paired state as far as the trip and memory paths care — a couple id
    /// to write under — without running `adopt`, which needs the whole backend.
    func setBackendCoupleIDForTesting(_ id: UUID?) {
        session.backendCoupleID = id
    }

    /// The sample couple from Mock/DemoData.swift, adopted the way a real couple would be, with no
    /// backend behind it (`-demoMode`, see App/DemoMode.swift). In this file because several of
    /// the fields it sets are `private(set)`.
    func applyDemoState() {
        session.couple = DemoData.couple
        travel.trips = DemoData.trips
        travel.flights = DemoData.flights
        travel.memories = DemoData.memories()
        session.hasCouple = true
        session.needsOnboarding = false
        // `-demoPartner none`: signed in on your own, which is the only state Home shows the
        // "Set up your partner" card in. The request lookup counts as answered, as the card waits for it.
        session.partnerConnected = DemoMode.argument("demoPartner") != "none"
        session.hasResolvedOutgoingConnectionRequest = true
        prompts.partnerConnectedCelebrationShown = DemoMode.argument("demoScreen") != "connected"
        prompts.setupChecklistDismissed = true
        subscription.apply(active: true, viewerHolds: true, tier: "premium", viewerStore: nil)
        session.hasResolvedOutgoingConnectionRequest = true
        session.hasLoadedCoupleState = true
        games.applyDemoState()
        myDrawingURL = DemoData.myDrawingURL
        partnerDrawingURL = DemoData.partnerDrawingURL
    }
}
#endif

extension AppModel: TravelStoreHost {
    var backendCoupleID: UUID? { session.backendCoupleID }
    var writeRefusedMessage: String? {
        get { prompts.writeRefusedMessage }
        set { prompts.writeRefusedMessage = newValue }
    }

    func refreshWidgets() {
        Task { await WidgetSnapshotWriter.refresh(appModel: self) }
    }
}
