//
//  PromptsState.swift
//  Twofold
//
//  The one-off things the app asks or tells somebody: the review prompt, the invite nudge, the
//  partner-connected celebration, the setup checklist, the lapse and disconnect notices, and a
//  refused write. Owned by `AppModel`, which forwards the old property names to it.
//

import Foundation
import Observation

@Observable
final class PromptsState: AccountScopedStore {
    /// Set by `AppModel.adoptSoloProfile(_:)` whenever it fires while the couple was still
    /// considered connected a moment ago — a partner removing you, or a partner deleting their own
    /// account, look identical from here. `HomeView` reads this once to explain why Trips/Memories/
    /// Flights just went quiet, instead of letting them silently empty out with no context.
    var partnerDisconnectedMessage: String?

    /// Set when a write was refused outright rather than merely failing to send — an RLS denial,
    /// which since 20261028000000 is what an unsubscribed couple gets for adding or editing.
    ///
    /// Exists because the optimistic-local-edit pattern these paths use is right for a dropped
    /// connection and wrong for a refusal. Offline, the edit is correct and lands later; refused,
    /// it is already gone and staying on screen is a lie that unwinds at the next relaunch.
    /// Cleared by whoever shows it.
    var writeRefusedMessage: String?

    /// Server-persisted "seen it" flags — deliberately not UserDefaults/@AppStorage, since those
    /// live in the app's local sandbox and get wiped on every uninstall/reinstall, showing these
    /// one-time prompts again even though nothing about the account changed. See
    /// `markPartnerConnectedCelebrationShown()`/`dismissSetupChecklist()`.
    var partnerConnectedCelebrationShown = false
    var setupChecklistDismissed = false

    /// Non-nil only while there's an unacknowledged "your subscription lapsed because {name}
    /// left" notice — set by `AppModel.adoptSoloProfile(_:)` from `leave_couple`'s server-captured
    /// snapshot (the ex-partner's name is already gone from `partner_name` by the time this
    /// loads). `HomeView` shows its `subscriptionLapsedCard` while this is set — see
    /// `markPartnerSubscriptionLapseAcknowledged()`. It used to be a whole screen shown by
    /// `RootView` in place of the non-dismissable paywall; both went when the paywall did.
    var partnerSubscriptionLapsedPartnerName: String?

    /// Set whenever a newly-crossed, not-yet-shown review milestone is detected — RootView
    /// presents `ReviewPromptView` as a sheet whenever this is non-nil. See
    /// `AppModel.checkReviewMilestones()`/`noteReviewMilestone(_:)`.
    var pendingReviewMilestone: ReviewMilestone?

    /// RootView presents `PartnerInviteNudgeView` as a sheet whenever this is true — see
    /// `AppModel.noteSoloActionCompleted()`.
    var pendingPartnerInviteNudge = false

    func reset() {
        // All of these carry a name — an ex-partner's.
        partnerDisconnectedMessage = nil
        partnerSubscriptionLapsedPartnerName = nil

        // Per-account "already seen" flags. Harmless next to the above, but they belong to whoever
        // dismissed them: a new account arriving to a pre-dismissed checklist and no
        // partner-connected celebration is still the previous account's state showing through.
        partnerConnectedCelebrationShown = false
        setupChecklistDismissed = false
        pendingReviewMilestone = nil
        pendingPartnerInviteNudge = false

        // Transient, but it refers to a write made by the previous account.
        writeRefusedMessage = nil
    }

    /// Flips instantly (so the caller's UI never shows the celebration twice in one session)
    /// and persists server-side in the background — see `BackendService.markPartnerConnectedCelebrationShown`.
    func markPartnerConnectedCelebrationShown() {
        guard !partnerConnectedCelebrationShown else { return }
        partnerConnectedCelebrationShown = true
        Task { await BackendService.markPartnerConnectedCelebrationShown() }
    }

    /// Same pattern as `markPartnerConnectedCelebrationShown()` — instant local flip (so the
    /// notice never comes back in the same session), persisted
    /// server-side in the background. Re-armable: `leave_couple` can set the underlying flag back
    /// to `false` again later, for a different relationship's same non-payer outcome.
    func markPartnerSubscriptionLapseAcknowledged() {
        guard partnerSubscriptionLapsedPartnerName != nil else { return }
        partnerSubscriptionLapsedPartnerName = nil
        Task { await BackendService.markPartnerSubscriptionLapseShown() }
    }

    /// Same pattern as `markPartnerConnectedCelebrationShown()` — instant local flip, persisted
    /// server-side in the background.
    func dismissSetupChecklist() {
        guard !setupChecklistDismissed else { return }
        setupChecklistDismissed = true
        Task { await BackendService.markSetupChecklistDismissed() }
    }

    /// Raises the partner-connected review milestone, once, when the caller has decided the couple
    /// has reached it — see `AppModel.checkReviewMilestones()`.
    func notePartnerConnectedMilestone() {
        guard pendingReviewMilestone == nil else { return }
        if ReviewPromptService.markShownIfEligible(.partnerConnected) {
            pendingReviewMilestone = .partnerConnected
        }
    }

    /// For the one milestone AppModel can't derive from its own state.
    func noteReviewMilestone(_ milestone: ReviewMilestone) {
        guard pendingReviewMilestone == nil, ReviewPromptService.markShownIfEligible(milestone) else { return }
        pendingReviewMilestone = milestone
    }

    /// Surfaces `PartnerInviteNudgeView` at most once a day, for somebody with nobody to invite
    /// yet — see `AppModel.noteSoloActionCompleted()`, which decides that.
    func noteSoloActionCompleted() {
        guard PartnerInviteNudgeService.isEligibleToday() else { return }
        pendingPartnerInviteNudge = true
        PartnerInviteNudgeService.markShown()
    }
}
