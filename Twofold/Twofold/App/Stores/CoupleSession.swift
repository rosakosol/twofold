//
//  CoupleSession.swift
//  Twofold
//
//  Who is signed in and with whom: the couple, whether one exists, how far onboarding got, the
//  invite code and the connection requests either way. Owned by `AppModel`, which forwards the old
//  names to it and keeps the work that spans every store — signing in and out, adopting a fetched
//  couple, onboarding — for itself.
//

import Foundation
import Observation

@Observable
final class CoupleSession: AccountScopedStore {
    var hasCouple: Bool = false
    /// Signed in, but this account never went through onboarding — it was created on the website
    /// by subscribing there, so it has an empty name, no partner, no anniversary and no invite.
    ///
    /// `hasCouple` used to be set true for anyone with a session at all, on the reasoning (stated
    /// in `loadSignedInState`'s own comment) that being authenticated proves onboarding happened.
    /// That held for exactly as long as the app was the only way to make an account. These people
    /// landed in `MainTabView` called "You", with no route back to the flow that collects any of
    /// it. `RootView` sends them to `OnboardingCoordinatorView` instead.
    ///
    /// Deliberately not set on the offline-cache path: a launch with no network looks identical to
    /// "no rows" from here, and re-onboarding somebody because their train went into a tunnel is a
    /// far worse failure than briefly showing a web account the app.
    var needsOnboarding = false

    /// Onboarding created this account and then did not finish — the questionnaire is answered and
    /// sitting in the profile, and only the invite/trial/paywall screens are left.
    ///
    /// Only meaningful while `needsOnboarding` is true. It is what lets the flow offer to resume
    /// instead of restarting, and it never opens the paywall: resuming lands on `.invitePartner`,
    /// which leads to the trial screen and the same non-dismissable wall.
    var hasSavedOnboardingProgress = false
    var couple: Couple = CoupleSession.placeholderCouple

    /// Whether the partner has actually redeemed an invite and joined — confirmed by the
    /// backend (an active `couples` row exists), not assumed the moment a code is shared.
    var partnerConnected: Bool = false
    var inviteCode: String?
    /// Incoming "someone wants to connect" requests awaiting my decision (I'm the inviter on
    /// each of these) — see `refreshPendingConnectionRequests()`/`respondToConnectionRequest(_:accept:)`.
    var pendingConnectionRequests: [BackendService.PendingConnectionRequest] = []
    /// My own outgoing request, if I redeemed a code and I'm still waiting on the inviter's
    /// decision — see `refreshPendingOutgoingConnectionRequest()`. `RootView` lets this bypass
    /// the forced re-subscribe paywall entirely (straight into `MainTabView`) for someone who
    /// isn't really solo, just not accepted yet; `HomeView` shows a persistent card for it, with
    /// the option to nudge the inviter — see `sendConnectionRequestReminder()`.
    var pendingOutgoingConnectionRequest: BackendService.OutgoingConnectionRequest?
    /// Whether `pendingOutgoingConnectionRequest` has been looked up yet this session.
    ///
    /// `nil` on that property means two different things — "there is no pending request" and "we
    /// have not asked yet" — and the paywall gate has to tell them apart. Someone who redeemed an
    /// invite and is waiting on the inviter must never be shown a paywall, and at launch the
    /// lookup is a network round trip that lands well after `hasCouple` flips true. Without this,
    /// the gate evaluated during that window and flashed the paywall at exactly the person it is
    /// meant to exempt.
    var hasResolvedOutgoingConnectionRequest = false

    /// Whether the couple's own state has been fetched yet.
    ///
    /// Everything derived from it defaults to the answer that means "something is missing":
    /// `needsOwnHomeCity` is `homeCity == nil`, `needsFirstTrip` is `trips.isEmpty`,
    /// `needsFirstFlight` likewise, and `partnerConnected` starts false. All four are true before
    /// the first fetch lands, so on every cold launch Home asserted that the city was unset and the
    /// trips and flights unadded, and Games locked the partner games — then took it all back a
    /// round trip later.
    ///
    /// Each of those is the subscription card's bug wearing different clothes, and the fix is the
    /// same: say nothing until there is something to say. Not one flag per derived value, because
    /// they all answer to the same fetch.
    var hasLoadedCoupleState = false

    /// Set once a real `couples` row exists for this user. Read-only on `AppModel`:
    /// `ExportDataView` needs the id to export the couple that is still together, and only the
    /// adopt paths write it.
    var backendCoupleID: UUID?

    func reset() {
        hasCouple = false
        // Account-scoped like everything else here, and the one whose absence had teeth: it
        // decides *which* root `OnboardingCoordinatorView` shows. Left set, signing out of an
        // account that had not finished onboarding lands on the first onboarding question instead
        // of `WelcomeView` — a screen with no back button, no sign-in button and nothing else to
        // tap, so the sign-out that was supposed to be the way out is itself a dead end. It also
        // leaks: the next account to sign in on this device inherits the flag and is sent through
        // onboarding it has already done.
        needsOnboarding = false
        // Same reasoning, one step along: left set, the next account to sign in on this phone is
        // offered somebody else's half-finished setup to resume.
        hasSavedOnboardingProgress = false
        partnerConnected = false
        inviteCode = nil
        backendCoupleID = nil
        hasLoadedCoupleState = false
        couple = Self.placeholderCouple
        // These carry the name of someone who asked to connect.
        pendingConnectionRequests = []
        pendingOutgoingConnectionRequest = nil
        // Left true, Home showed the next account the generic invite card before its own lookup
        // had run, to someone who may well have a request waiting. Signing in resolves it again.
        hasResolvedOutgoingConnectionRequest = false
    }

    static var placeholderCouple: Couple {
        Couple(
            partnerA: Person(name: "You", accentColor: Person.palette[1]),
            partnerB: Person(name: "Partner", accentColor: Person.palette[0]),
            startedDatingOn: .now
        )
    }

    /// Incoming connection requests (double verification — see the migration's own header
    /// comment) — safe to call any time, including while already connected (just returns
    /// empty), so call sites don't need to guard on `partnerConnected` themselves.
    func refreshPendingConnectionRequests() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        pendingConnectionRequests = (try? await BackendService.fetchPendingConnectionRequests()) ?? []
    }

    /// My own outgoing request (see `pendingOutgoingConnectionRequest`'s doc comment). Guarded on
    /// `!partnerConnected` for two reasons: efficiency (this now runs on every foreground — see
    /// `RootView.refreshPendingOutgoingConnectionRequestIfNeeded` — so a genuinely paired couple
    /// shouldn't pay for a network round trip that can only ever come back empty for them), and
    /// correctness. The "only" in the old version of this comment was wrong: nothing stops
    /// redeeming a second code while a first request is still unresolved, so
    /// `fetchMyOutgoingConnectionRequest()`'s "most recent pending" query can keep surfacing an
    /// abandoned request from *before* pairing even after a different one got accepted — without
    /// this guard, Home's pending-invite card would wrongly show for someone who's actually
    /// already connected.
    func refreshPendingOutgoingConnectionRequest() async {
        if DemoMode.isOn { return }  // -demoMode: the sample couple, nothing fetched
        guard !partnerConnected else {
            pendingOutgoingConnectionRequest = nil
            hasResolvedOutgoingConnectionRequest = true
            return
        }
        // Retried once, because a failure here is not the same as an empty answer and the two are
        // indistinguishable downstream.
        //
        // `pendingOutgoingConnectionRequest == nil` means both "there is no request" and "we could
        // not find out". RootView reads nil as no-exemption and shows the paywall; Home reads it as
        // not-invited and shows the generic invite card. So one failed call — a token still
        // settling moments after sign-in is enough — flashes a paywall at someone waiting on their
        // partner, then corrects itself when the next refresh succeeds. That is what this fixes.
        //
        // Still resolves after the second attempt rather than looping: a network that is genuinely
        // down must not hold anyone on a loading screen forever, and after two tries the honest
        // answer is that we do not know.
        var fetched: BackendService.OutgoingConnectionRequest?
        var succeeded = false
        for attempt in 0..<2 {
            do {
                fetched = try await BackendService.fetchMyOutgoingConnectionRequest()
                succeeded = true
                break
            } catch {
                // A short pause before the retry. The failure this exists for is a session that is
                // a moment from being usable, not one that is broken.
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(400)) }
            }
        }

        // Only overwrite what we know with what we found if we actually found out. A failed pair of
        // attempts leaves any previously-known request standing rather than erasing it.
        if succeeded { pendingOutgoingConnectionRequest = fetched }
        hasResolvedOutgoingConnectionRequest = true
    }

    /// Nudges the inviter on `pendingOutgoingConnectionRequest`. Returns an error message on
    /// failure (including the RPC's own cooldown-rejection text), nil on success — same shape as
    /// `removePartner()`.
    @discardableResult
    func sendConnectionRequestReminder() async -> String? {
        guard let request = pendingOutgoingConnectionRequest else { return "No pending request to remind." }
        do {
            try await BackendService.sendConnectionRequestReminder(requestID: request.id)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
