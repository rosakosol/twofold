//
//  GameSharedStates.swift
//  Twofold
//
//  Small pieces of UI shared by all four game views — the universal skip affordance and the
//  abandoned/error fallbacks. The mid-game "waiting for partner" state is gone — each partner
//  now walks straight through their own rounds independently; see GameCompletionView for the
//  new end-of-my-rounds waiting state instead.
//

import SwiftUI

/// Content-safety requirement: every prompt must be skippable.
struct SkipButton: View {
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button("Skip", action: action)
            .font(.subheadline)
            .foregroundStyle(Theme.subtleInk)
            .disabled(isDisabled)
    }
}

struct GameAbandonedState: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "flag.slash.fill").font(.largeTitle).foregroundStyle(Theme.subtleInk)
            Text("This game was left unfinished.")
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The "Report a Problem"/"Send Feedback" items shared by every game screen's overflow menu —
/// `mailto:` links (see `SupportMail`), with `showingNoMailAppAlert` flipped true if nothing on
/// the device can actually open one (the caller owns presenting that alert, since it needs to
/// live on the same view as the `Menu` these sit inside).
struct SupportMenuItems: View {
    let userID: UUID
    let context: String
    @Binding var showingNoMailAppAlert: Bool

    var body: some View {
        Button {
            open(SupportMail.reportProblemURL(userID: userID, context: context))
        } label: {
            Label("Report a Problem", systemImage: "exclamationmark.bubble")
        }
        Button {
            open(SupportMail.feedbackURL())
        } label: {
            Label("Send Feedback", systemImage: "envelope")
        }
    }

    private func open(_ url: URL?) {
        guard let url else {
            showingNoMailAppAlert = true
            return
        }
        UIApplication.shared.open(url) { success in
            if !success { showingNoMailAppAlert = true }
        }
    }
}

/// Paired with `SupportMenuItems` — attach to whichever view hosts the `Menu`, so a failed
/// `mailto:` open (no mail client configured) still tells the person how to reach out.
extension View {
    func noMailAppAlert(isPresented: Binding<Bool>) -> some View {
        alert("Couldn't Open Mail", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No mail app is set up on this device. You can reach us at \(SupportMail.address).")
        }
    }
}

/// Stands in for the native back button on every typed game view — those hide the real one
/// (`.navigationBarBackButtonHidden`) and disable the swipe gesture
/// (`.interactivePopGestureDisabled`) while a round is in play, so this is the *only* way back,
/// routed through `GameSessionStore.goBack(myID:)`/a leave-confirmation instead of an instant pop.
struct GameBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.backward")
        }
    }
}

/// Paired with `GameBackButton` — shown when the back button is tapped at round 1, where there's
/// no previous round left to revisit. "Leave" abandons the session (see
/// `BackendService.abandonGameSession`); the couple's daily-question RPC and every deck/game
/// entry point already skip abandoned sessions when looking for one to resume, so this always
/// results in a clean fresh start rather than a stuck "unfinished" state.
extension View {
    func gameLeaveConfirmation(isPresented: Binding<Bool>, onLeave: @escaping () -> Void) -> some View {
        alert("Leave game?", isPresented: isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive, action: onLeave)
        } message: {
            Text("Your progress on this game will be lost.")
        }
    }
}

struct GameErrorState: View {
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.heartRed)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
