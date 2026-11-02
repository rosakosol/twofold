//
//  OnboardingModel.swift
//  Twofold
//
//  Everything collected across the registration/onboarding flow, before it gets
//  folded into the real AppModel state via `AppModel.completeOnboarding`.
//

import Foundation
import Observation

@Observable
final class OnboardingModel {
    var path: [OnboardingStep] = []
    var role: OnboardingRole = .inviter

    /// The account already exists and is already signed in — a website subscription, which creates
    /// the `auth.users` row without any of what onboarding collects (see `AppModel
    /// .needsOnboarding`). The flow is otherwise identical; three things change:
    ///
    ///   1. `WelcomeView` is not the root, because "Get started"/"Sign in" are both already done.
    ///   2. `TwofoldPreviewView` skips `.saveAccount` — there is no account to create. It applies
    ///      everything collected to the existing profile at exactly the point `SaveAccountView`
    ///      would have, so the persistence boundary does not move.
    ///   3. `InvitePartnerView` skips `.trialTrust`/`.paywall` — they paid on the web already, and
    ///      showing a paywall to somebody who is mid-subscription is its own bug.
    var isResumingAuthenticatedAccount = false

    /// This account is actually paying, right now — the server's answer, adopted by
    /// `loadSignedInState` before onboarding starts.
    ///
    /// Separate from `isResumingAuthenticatedAccount`, and the separation is the point. Skipping
    /// the paywall used to key off that flag, on the reasoning written above: a resuming account
    /// "paid on the web already". That was true of the population the flag was introduced for and
    /// was never true of the flag itself, which means nothing more than "no `onboarding_completed_at`".
    ///
    /// Four ways to hold it, one of which involves money. Somebody who signed in to the feedback
    /// board on the website — that page is a magic-link login whose `next` defaults to `/feedback`,
    /// with no checkout anywhere near it. Somebody who quit in-app onboarding after `.saveAccount`,
    /// which happens before the paywall, so the account outlives the session that was going to pay
    /// for it. A web subscriber who has since lapsed. And, finally, an actual paying web
    /// subscriber.
    ///
    /// The first three were routed past the paywall without ever being shown it. They do not get
    /// anything for free — writes are refused by the database (20261028000000) — which is the
    /// worse outcome of the two: an app that silently declines to save anything, and no paywall
    /// ever shown to explain why.
    var hasActiveSubscription = false

    init() {
        #if DEBUG
        // Opens onboarding straight at one step, from `-onboardingStep <case>` — the same
        // DEBUG-only launch-argument trick `NotificationRouter` uses to exercise a cold-launch
        // notification tap, and for the same reason: the screen worth testing is otherwise
        // nineteen screens and a dozen text fields away, or (for `createAccount`) behind a live
        // invite code. `SignInUITests`' own header is about exactly this cost.
        //
        // Seeds the two names as well, since the screens it reaches read them for their subtitles
        // and an empty one renders a sentence with a hole in it. DEBUG-only, so it cannot exist in
        // a shipped build. Used by `LegalConsentUITests`.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-onboardingStep"), flag + 1 < arguments.count,
           let step = OnboardingStep(debugArgument: arguments[flag + 1]) {
            firstName = "Sam"
            partnerName = "Alex"
            path = [step]
        }
        #endif
    }

    // Account
    var firstName: String = ""
    var email: String = ""
    var password: String = ""

    // Home city
    var homeCity: Place?

    // Partner connection
    var inviteCode: String?

    /// How `inviteCode` reached us, and therefore whether redeeming it pairs immediately or raises
    /// a request the inviter approves (see migration 20261008000000).
    ///
    /// It has to be carried rather than inferred. `HomeCityView` does the redeeming for anyone who
    /// arrives without an account, and both routes land there: a tapped deep link via
    /// `resetForNewInvite`, and a typed code via `EnterPartnerCodeView`, which appends `.joinInvite`
    /// when there is no account yet. That screen used to hardcode `.link` on the strength of a
    /// comment saying only a link could get there. It was wrong, and the effect was that anybody
    /// signing up fresh with a typed code was paired with no approval at all — the one thing typing
    /// a code is supposed to require.
    ///
    /// Defaults to `.code`, which is the safe end: the worst a wrong `.code` does is ask someone to
    /// confirm a pairing they wanted.
    var inviteOrigin: BackendService.InviteOrigin = .code
    var inviterName: String?
    var inviterAvatarURL: URL?
    /// Whether the inviter lookup has come back — win, lose or draw. Distinct from `inviterName
    /// != nil`, which cannot tell "still asking" apart from "asked, and there is no name", and so
    /// renders the fallback as though it were the answer. `JoinInviteView`'s headline names the
    /// inviter, so without this it announces "Your partner invited you" and then visibly rewrites
    /// itself to "Max invited you" a moment later.
    var hasResolvedInviterName = false
    /// True once account creation has happened — lets `EnterPartnerCodeView` decide
    /// whether it still needs to route through account creation or can connect directly.
    var hasAccount: Bool = false

    // Next trip
    var draftedTrip: Trip?

    // MARK: - New default onboarding flow (situation → ... → save account)
    //
    // Everything below accumulates purely locally — account creation now happens at the
    // very end of the flow (`SaveAccountView`), so none of this can be persisted to
    // Supabase until then. `AppModel.completeOnboarding` is the single place it all gets
    // applied, in one shot, once a real session exists.

    var situation: RelationshipSituation?
    var frequency: TravelFrequency?
    var attribution: AttributionSource?
    var goals: Set<OnboardingGoal> = []

    /// The partner's name/city as *typed by this user* — personalization only, not a real
    /// linked account. Real pairing still happens via the existing invite-code flow, later,
    /// from the home screen's setup checklist.
    var partnerName: String = ""
    var partnerCity: Place?
    var anniversaryDate: Date?

    /// Optional at every point it is asked for — the onboarding screen has a Skip, and Settings
    /// treats it as a field you may simply not fill in. Nil here means "not given", never
    /// "not asked".
    var birthday: Birthday?

    var userGender: Gender?
    var partnerGender: Gender?

    /// The word later screens use in place of the generic "their" when referring to the
    /// partner by name — "his"/"her" for a selected gender, or "their" as a safe default if
    /// gender was never asked/answered.
    var partnerPossessive: String {
        partnerGender?.possessive ?? "their"
    }

    /// Picked photos held as raw JPEG data until account creation succeeds — there's no
    /// session to upload against until then. `partnerPhotoData` is just this user's
    /// placeholder guess of their partner's photo (stored as this user's own
    /// `partner_avatar_path`, not the partner's `avatar_path`).
    var selfPhotoData: Data?
    var partnerPhotoData: Data?

    /// Set when redeeming connected the two of them outright, which a tapped link now does (see
    /// migration 20261008000000). The screens that say "request sent, we'll let you know" are
    /// wrong in that case and are skipped.
    var connectedOnRedeem = false

    /// What the paywall's `onSubscribed` reported, for `PurchaseSuccessView`'s subtitle: a trial
    /// that really started, a paid purchase, or a restore. `nil` until then.
    var subscriptionOutcome: SubscriptionOutcome?

    /// Set once the user has responded to the system notification prompt (either way) —
    /// lets the app avoid ever re-prompting.
    var notificationsGranted: Bool?

    /// Cache backing `illustrativeOriginCity`, picked once and reused so the notifications
    /// and Live Activity sell screens show the same made-up departure city as each other.
    private var cachedIllustrativeOriginCity: Place?

    /// The illustrative departure city used by the notification/Live Activity sell screens'
    /// example flight (partner's city → user's city, matching the "reunion" framing used
    /// throughout onboarding) — unless the couple lives in the same city, which would make
    /// that example flight depart and arrive in the same place. In that case a random other
    /// city stands in instead, chosen once and cached so both screens agree on the same one.
    var illustrativeOriginCity: Place? {
        guard let homeCity, let partnerCity else { return partnerCity }
        guard homeCity.city == partnerCity.city && homeCity.country == partnerCity.country else {
            return partnerCity
        }
        if cachedIllustrativeOriginCity == nil {
            cachedIllustrativeOriginCity = Place.commonCities.filter { $0.city != homeCity.city }.randomElement()
        }
        return cachedIllustrativeOriginCity
    }

    /// Called when a sign-in attempt anywhere in onboarding (or the returning-user sign-in
    /// sheet) resolves to a previously-deleted account — see `BackendError.accountDeleted`.
    /// A full wipe back to a brand-new `OnboardingModel()`'s defaults, not just the account
    /// fields — every questionnaire answer collected so far gets discarded too, so this is a
    /// genuinely fresh flow rather than one that quietly remembers anything about the previous
    /// attempt. `path = []` also pops all the way back to `WelcomeView`, the root of
    /// `OnboardingCoordinatorView`'s NavigationStack.
    func resetAfterDeletedAccount() {
        path = []
        role = .inviter
        isResumingAuthenticatedAccount = false

        firstName = ""
        email = ""
        password = ""

        homeCity = nil

        inviteCode = nil
        inviterName = nil
        inviterAvatarURL = nil
        hasResolvedInviterName = false
        hasAccount = false
        redeemedInviteCode = nil
        inviteOrigin = .code

        draftedTrip = nil

        situation = nil
        frequency = nil
        attribution = nil
        goals = []

        partnerName = ""
        partnerCity = nil
        anniversaryDate = nil

        userGender = nil
        partnerGender = nil

        selfPhotoData = nil
        partnerPhotoData = nil

        notificationsGranted = nil
        subscriptionOutcome = nil

        cachedIllustrativeOriginCity = nil
    }

    /// Who an invite code belongs to. `BackendService.inviterInfo` in the app; a test hands in its
    /// own, to hold an answer in the air or say "no such code".
    @ObservationIgnored var inviterLookup: (String) async throws -> BackendService.InviterInfo? = {
        try await BackendService.inviterInfo(forCode: $0)
    }

    func resetForNewInvite(code: String) {
        role = .invitee
        inviteCode = code
        // The only caller is a tapped invite link.
        inviteOrigin = .link
        path = [.joinInvite]
        // `get_invite_code_inviter_info` deliberately works without an authenticated session
        // (see its migration's own comment) specifically so this — a cold deep-link tap, before
        // any account exists — can show the real inviter on JoinInviteView. Fired async rather
        // than blocking the navigation above; JoinInviteView just updates once this resolves.
        //
        // The previous inviter is cleared here, before the Task, so not even one frame of the new
        // invite shows the last one's name.
        let generation = beginInviterLookup()
        Task { await finishInviterLookup(code: code, generation: generation) }
    }

    enum InviterLookupResult: Equatable {
        case found
        /// The server answered, and the code is not a pending, unexpired invite.
        case notFound
        /// No answer at all — offline, most likely. Not evidence the code is wrong.
        case failed
    }

    /// Bumped by every lookup, so only the newest one may write its answer.
    @ObservationIgnored private var inviterLookupGeneration = 0

    /// Looks up who `code` belongs to and puts them on the model for the invite screens.
    ///
    /// Clears the previous inviter first. A second link tapped in the same session used to show
    /// the first inviter's name, unredacted, until its own lookup came back — and two quick taps
    /// could resolve out of order, so the older code's name could win for good. Each lookup now
    /// writes only if no newer one has started since.
    @discardableResult
    func resolveInviter(code: String) async -> InviterLookupResult {
        await finishInviterLookup(code: code, generation: beginInviterLookup())
    }

    private func beginInviterLookup() -> Int {
        inviterLookupGeneration += 1
        inviterName = nil
        inviterAvatarURL = nil
        hasResolvedInviterName = false
        return inviterLookupGeneration
    }

    private func finishInviterLookup(code: String, generation: Int) async -> InviterLookupResult {
        let result: InviterLookupResult
        let info: BackendService.InviterInfo?
        do {
            info = try await inviterLookup(code)
            result = info == nil ? .notFound : .found
        } catch {
            info = nil
            result = .failed
        }
        guard generation == inviterLookupGeneration else { return result }
        inviterName = info?.name
        inviterAvatarURL = info?.avatarURL
        // Set on the failure path too — a lookup that came back empty is still a lookup that
        // finished, and the screen has to stop waiting and show its fallback.
        hasResolvedInviterName = true
        return result
    }

    /// "Have an invite code instead?", for somebody with no account yet. Returns the message to
    /// show under the field, or nil once the flow has moved on.
    ///
    /// The code is checked here, before anything else. It used to be pushed straight on to
    /// `.joinInvite` without a lookup, which left that screen's headline redacted for good (only a
    /// tapped link ever resolved the inviter), and a mistyped or expired code was only refused at
    /// Home City — after an account had been made for it, with "email already exists" waiting one
    /// screen back.
    func enterTypedCode(_ raw: String) async -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch await resolveInviter(code: code) {
        case .found:
            inviteCode = code
            // Typed by hand, so it stays a request the inviter approves.
            inviteOrigin = .code
            push(.joinInvite)
            return nil
        case .notFound:
            return "We couldn't find that code — check it with your partner."
        case .failed:
            return "We couldn't check that code. Check your connection and try again."
        }
    }

    /// Pushes `step`, unless it is already on top.
    ///
    /// The question screens advance on a tap of the answer, and a quick double tap used to push
    /// the next question twice, so Back showed the same question again.
    func push(_ step: OnboardingStep) {
        guard path.last != step else { return }
        path.append(step)
    }

    /// Moves on from the screen that has just created the account, leaving nothing behind it.
    ///
    /// Appending kept the sign-up screens one swipe back. Swiping there offered a signed-in person
    /// a form to sign up again: by email, "already exists"; by Apple or Google with another ID, a
    /// second account that the questionnaire was then written to. The screen this lands on hides
    /// its back button too, because the root under it is Welcome.
    func continueAfterAccountCreated(to step: OnboardingStep) {
        path = [step]
    }

    /// The invite code this account redeemed, once it has.
    var redeemedInviteCode: String?

    /// The code `HomeCityView` should redeem on Continue, if any. Nil once redeemed: swiping back
    /// from the photo screen and pressing Continue again redeemed a code that was already used,
    /// and the server's refusal left the person stuck on Home City.
    var codeToRedeem: String? {
        guard role == .invitee, let inviteCode, inviteCode != redeemedInviteCode else { return nil }
        return inviteCode
    }
}
