//
//  ResumeSetupView.swift
//  Twofold
//
//  The screen for somebody who started setting Twofold up, made their account, and stopped.
//
//  That is a specific and fairly likely person. The account is created at `.saveAccount`, which is
//  after every question and three screens before a paywall that cannot be dismissed — so "quit on
//  the paywall" leaves a real, fully populated account with `onboarding_completed_at` still null.
//  Before this screen existed they were put back on question one, with an `OnboardingModel` rebuilt
//  empty on every launch, and asked for their name, their partner's name, their cities and their
//  anniversary again — all of which were already in their profile, and none of which the flow read
//  back. The paywall they had walked away from was then eighteen screens further away than when
//  they left.
//
//  So this says the two things they need: your setup was kept, and here is the short way back to
//  it. Resuming lands on `.invitePartner`, which leads to the trial screen and the same paywall.
//  Nothing here is a way past it.
//

import SwiftUI

struct ResumeSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(OnboardingModel.self) private var onboarding

    /// Offered because the alternative reading of this screen is "that isn't me".
    ///
    /// A shared phone, a second account, an address typed wrong — in every one of those the
    /// person does not want this setup resumed, and without a way out the only honest option
    /// left is force-quitting. Signing out is what makes a different signup possible: `WelcomeView`
    /// is the other root of this same stack, and `resetAccountScopedState()` clearing
    /// `needsOnboarding` is what lets sign-out actually land there rather than back here.
    ///
    /// Confirmed rather than immediate, because the account left behind is real and the way back
    /// into it is a password.
    @State private var showingStartFreshConfirmation = false

    private var greeting: String {
        let name = appModel.session.couple.partnerA.name
        // `fetchOwnProfile` substitutes "You" for an empty name, so it is never blank — but it is
        // also not a name, and "Welcome back, You" is worse than no name at all.
        return name.isEmpty || name == "You" ? "Welcome back" : "Welcome back, \(name)"
    }

    /// Which flow this account was part-way through. An invitee's account is made at "Create
    /// account", early in their own short flow, and resuming them into the inviter's tail minted
    /// them a code of their own and showed them a paywall — see `OnboardingResume`.
    private var plan: OnboardingResume.Plan {
        OnboardingResume.plan(
            pendingRequestInviterName: appModel.session.pendingOutgoingConnectionRequest?.inviterFirstName,
            savedInvite: BackendService.currentUserID.flatMap { OnboardingResume.savedInvite(for: $0) }
        )
    }

    var body: some View {
        OnboardingScaffold(
            title: greeting,
            subtitle: "You're nearly there — we saved everything you told us, so there's no need to go through it again.",
            centered: true,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    switch plan {
                    case .inviter:
                        savedRow("person.fill", "Your name and \(partnerDescription)")
                        savedRow("mappin.and.ellipse", "Where you both are")
                        savedRow("heart.fill", "Your anniversary")
                    case .inviteeAwaitingReply(let inviterName):
                        savedRow("person.fill", "Your account")
                        savedRow("heart.fill", "Your request to connect with \(inviterName)")
                    case .inviteeToRedeem:
                        savedRow("person.fill", "Your account")
                        savedRow("envelope.fill", "Your invite code")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            },
            primaryTitle: "Pick up where you left off",
            primaryAction: { OnboardingResume.apply(plan, to: onboarding) },
            secondaryTitle: "Start a new signup",
            secondaryAction: { showingStartFreshConfirmation = true }
        )
        .confirmationDialog(
            "Start a new signup?",
            isPresented: $showingStartFreshConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start a new signup") { Task { await appModel.signOut() } }
            Button("Keep this one", role: .cancel) {}
        } message: {
            // Says what happens to the account they are walking away from, because it does not
            // disappear and the address stays taken — `SaveAccountView` answers a reused one with
            // "An account with this email already exists" and a Sign In button. Being told that
            // now is better than meeting it four screens into a second attempt.
            Text("You'll be signed out so you can sign up with a different email. This account stays as it is — sign in with it any time to come back.")
        }
    }

    /// The partner's name when there is one, because seeing it is half the proof that the setup
    /// really was kept.
    private var partnerDescription: String {
        let partner = appModel.session.couple.partnerB.name
        return partner.isEmpty || partner == "Partner" ? "your partner's" : "\(partner)'s"
    }

    private func savedRow(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .accessibilityHidden(true)
            Label(text, systemImage: systemImage)
                .labelStyle(.titleOnly)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        ResumeSetupView()
    }
    .environment(AppModel())
    .environment(OnboardingModel())
}
