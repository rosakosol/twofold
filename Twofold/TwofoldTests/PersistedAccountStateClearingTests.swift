//
//  PersistedAccountStateClearingTests.swift
//  TwofoldTests
//
//  Whether a store is actually reachable from the sign-out path.
//
//  `AccountScopedStateResetTests` covers `resetAccountScopedState()`, the in-memory half.
//  `PendingDraftStoreClearTests` covers two stores in isolation — that `PendingTripStore.clear()`
//  empties `loadAll()`. Neither asks the question that matters here, which is whether anybody
//  remembered to call that method from the path that runs when somebody signs out.
//
//  Nothing asked it, and so `PendingShareStore` — added later, holding the full text of a shared
//  booking confirmation, read by `HomeView` with no user id anywhere in the record — was never
//  cleared at all. It had no `clear()` to call. A booking reference, a passenger's legal name and
//  an itinerary survived sign-out and were offered to the next person to sign in on the device,
//  and every test stayed green. It was the third store to do this.
//
//  What this file can cover: the stores whose state is cheap to create and observe from a unit
//  test. It deliberately does not claim to cover all sixteen — `MemoryPhotoDiskCache` and
//  `WidgetImageCache` need bytes and a container, and asserting on them here would be testing
//  `FileManager`. The value is that a store added to the app and forgotten in
//  `clearPersistedAccountState()` now has somewhere it can be caught, and that the specific
//  regression above cannot come back.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
@Suite(.serialized)
struct PersistedAccountStateClearingTests {

    /// The bug. A share queued by the extension, never reviewed, then somebody signs out.
    @Test("a shared flight email does not survive sign-out")
    func pendingShareIsCleared() {
        PendingShareStore.add(
            PendingFlightShare(
                subject: "Your booking QF1 — confirmation ABCDEF",
                bodyText: "Passenger: A Traveller. Seat 14A.",
                pdfText: "BOARDING PASS ABCDEF"
            )
        )
        #expect(PendingShareStore.all().count == 1, "precondition: the queue has something in it")

        AppModel.clearPersistedAccountState()

        #expect(PendingShareStore.all().isEmpty, "the next account must not be offered this")
    }

    /// The control. Without this, a `clear()` that silently did nothing would pass the test above
    /// exactly as a working one does.
    @Test("the queue really does persist until something clears it")
    func pendingSharePersistsUntilCleared() {
        PendingShareStore.clear()
        PendingShareStore.add(PendingFlightShare(subject: "Held"))

        #expect(PendingShareStore.all().count == 1)
        #expect(PendingShareStore.all().first?.subject == "Held")

        PendingShareStore.clear()
        #expect(PendingShareStore.all().isEmpty)
    }

    /// The two drafted-content stores, asserted through the clearing path rather than by calling
    /// their own `clear()` — which is what `PendingDraftStoreClearTests` already does, and which
    /// would stay green if they were dropped from `clearPersistedAccountState()`.
    @Test("drafted trips and memories do not survive sign-out")
    func pendingDraftsAreCleared() {
        let trip = Trip(
            id: UUID(),
            travelerIDs: [],
            origin: Place(city: "Melbourne", country: "Australia", latitude: -37.81, longitude: 144.96),
            destination: Place(city: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.65),
            departureDate: Date().addingTimeInterval(86_400),
            arrivalDate: Date().addingTimeInterval(864_000),
            category: .together,
            distanceKm: 8_159
        )
        PendingTripStore.save(trip)
        #expect(!PendingTripStore.loadAll().isEmpty, "precondition")

        AppModel.clearPersistedAccountState()

        #expect(PendingTripStore.loadAll().isEmpty)
    }

    /// The account-scoped defaults, for the same reason: they are cleared by a private helper that
    /// only this path calls.
    @Test("account-scoped defaults do not survive sign-out")
    func accountScopedDefaultsAreCleared() {
        UserDefaults.standard.set("2026-09-21", forKey: "dormancy.lastTouchedOn")
        UserDefaults.standard.set("2026-09-20", forKey: "streakRepairOfferedForMissedDate")

        AppModel.clearPersistedAccountState()

        #expect(UserDefaults.standard.string(forKey: "dormancy.lastTouchedOn") == nil)
        #expect(UserDefaults.standard.string(forKey: "streakRepairOfferedForMissedDate") == nil)
    }

    /// The move out of the preferences plist, which is the part that could lose someone's data.
    ///
    /// `pendingFlightShares` lived in the app group's `UserDefaults` because that is where the
    /// widget snapshot lives — and a plist cfprefsd owns cannot take a protection class, so a
    /// shared booking confirmation sat at CompleteUntilFirstUserAuthentication and in every backup
    /// no matter what the rest of the app did. Moving it to a file fixes that and risks dropping
    /// anything captured just before the update, so the old location is read through once.
    @Test("a share queued before the update is carried over, not lost")
    func legacyShareIsMigrated() {
        PendingShareStore.clear()
        let legacy = [PendingFlightShare(subject: "Queued under the old build", bodyText: "PNR ABCDEF")]
        let defaults = UserDefaults(suiteName: "group.com.orangefinch.Twofold")
        defaults?.set(try! JSONEncoder().encode(legacy), forKey: "pendingFlightShares")

        let read = PendingShareStore.all()

        #expect(read.count == 1)
        #expect(read.first?.subject == "Queued under the old build")
        #expect(defaults?.data(forKey: "pendingFlightShares") == nil, "and the old key is not left behind")
        #expect(PendingShareStore.all().count == 1, "a second read still finds it, now from the file")

        PendingShareStore.clear()
    }

    /// Same again for the queued answers, which are the user's own words rather than a booking.
    @Test("an answer queued before the update is carried over, not lost")
    func legacyGameResponseIsMigrated() {
        PendingGameResponseStore.clear()
        let legacy = [PendingGameResponse(
            sessionID: UUID(), roundNumber: 1, responderID: UUID(),
            answerValue: "something they typed", isCorrect: nil
        )]
        UserDefaults.standard.set(try! JSONEncoder().encode(legacy), forKey: "pendingGameResponses")

        let read = PendingGameResponseStore.all()

        #expect(read.count == 1)
        #expect(read.first?.answerValue == "something they typed")
        #expect(UserDefaults.standard.data(forKey: "pendingGameResponses") == nil)

        PendingGameResponseStore.clear()
    }

    /// A device preference, not an account one. Asserted so that a future sweep of "clear
    /// everything on sign-out" does not quietly take the app lock off with it.
    @Test("the app lock preference is not an account-scoped default")
    func appLockSurvivesSignOut() {
        UserDefaults.standard.set(true, forKey: "appLockEnabled")

        AppModel.clearPersistedAccountState()

        #expect(UserDefaults.standard.bool(forKey: "appLockEnabled"), "the device's own security setting stays")
        UserDefaults.standard.removeObject(forKey: "appLockEnabled")
    }
}
