//
//  OnboardingCoordinatorView.swift
//  Twofold
//

import SwiftUI
import GoogleSignIn
import PostHog

struct OnboardingCoordinatorView: View {
    @Environment(AppModel.self) private var appModel
    @State private var onboarding = OnboardingModel()
    @State private var showingPasswordReset = false
    @State private var showingExitConfirmation = false
    @State private var passwordRecoveryError: String?

    var body: some View {
        NavigationStack(path: $onboarding.path) {
            Group {
                if appModel.needsOnboarding, appModel.hasSavedOnboardingProgress {
                    // Onboarding already got as far as making this account, so the questionnaire is
                    // answered and sitting in their profile. Starting them at question one asks for
                    // all of it a second time, having read none of it back.
                    //
                    // Checked before the branch below rather than inside it, because the two want
                    // different roots, not different copy on the same one.
                    ResumeSetupView()
                        .postHogScreenView("Onboarding: Resume Setup")
                } else if appModel.needsOnboarding {
                    // The first real screen, as the stack's root rather than pushed onto it. Seeding
                    // `path = [.situation]` instead would leave `WelcomeView` sitting underneath,
                    // one back-swipe away — and its two buttons are "Get started" and "Sign in",
                    // both meaningless to somebody who is already signed in.
                    RelationshipSituationView()
                        .postHogScreenView(OnboardingStep.situation.analyticsName)
                        // Every other onboarding screen is pushed, so it has a back button. This one
                        // is the stack's root, so it does not — and unlike the `WelcomeView` root
                        // below, the person looking at it is already signed in. Navigating back
                        // through the flow lands here, and there was then nothing at all to tap.
                        // A device got stuck exactly this way, and reinstalling did not clear it,
                        // because the Supabase session is in the Keychain and outlives the app.
                        .toolbar {
                            // Back to `WelcomeView` — the "Get started"/"Sign in" screen, which is
                            // this same stack's other root. Deliberately not a way *past*
                            // onboarding: there is no skip here, and reaching the app still means
                            // finishing the flow.
                            //
                            // It signs out, and it has to. Welcome's two buttons are "Get started"
                            // and "Sign in", both meaningless to somebody who already has a
                            // session — which is why this flow was built without a back-swipe to
                            // it in the first place. Worse, a session left alive would put them
                            // right back on this question at the next launch, so a back button
                            // that only changed the screen would undo itself.
                            //
                            // `resetAccountScopedState()` clearing `needsOnboarding` is what makes
                            // this land on Welcome rather than back here; before that fix, signing
                            // out returned to this very screen.
                            ToolbarItem(placement: .topBarLeading) {
                                Button {
                                    showingExitConfirmation = true
                                } label: {
                                    // Spelled out rather than a bare chevron: a lone back arrow on
                                    // a stack root reads as "undo one step", and this gives up a
                                    // session.
                                    Label("Back", systemImage: "chevron.backward")
                                }
                            }
                        }
                        // Asked rather than done, because "back" is not normally destructive and
                        // this is.
                        //
                        // Worded around the answers rather than the session, on purpose. Everyone
                        // who reaches this screen does technically hold one — it is the only
                        // reason `loadSignedInState` set `needsOnboarding` at all — but nobody
                        // here has *experienced* signing in: they were part-way through setting
                        // up. Telling them they will be "signed out" describes a state they do not
                        // believe they are in. What they actually lose is the run of answers
                        // behind them, and that is what this says.
                        .confirmationDialog(
                            "Go back to the start?",
                            isPresented: $showingExitConfirmation,
                            titleVisibility: .visible
                        ) {
                            // Not `.destructive`: nothing is destroyed. The account stays, and the
                            // answers it would be protecting do not exist at question one. It is
                            // confirmed at all only because it gives up the session, so the way
                            // back in is a password rather than a tap.
                            Button("Go back") {
                                Task { await appModel.signOut() }
                            }
                            Button("Keep setting up", role: .cancel) {}
                        } message: {
                            Text(exitConfirmationMessage)
                        }
                } else {
                    WelcomeView()
                        .postHogScreenView("Onboarding: Welcome")
                }
            }
            .navigationDestination(for: OnboardingStep.self) { step in
                destination(for: step)
                    .postHogScreenView(step.analyticsName)
            }
        }
        .environment(onboarding)
        .task {
            // Read once, into the model the whole flow already reads from, so no screen needs its
            // own AppModel lookup to know which variant it is in.
            onboarding.isResumingAuthenticatedAccount = appModel.needsOnboarding
            // Read here too, and kept apart from the flag above: one says the account already
            // exists, the other says it is paying, and only the second may skip a paywall.
            // `loadSignedInState` adopts the profile before routing here, so this is the server's
            // answer rather than a guess.
            onboarding.hasActiveSubscription = appModel.isSubscriptionActive
            // Put the two names back into the flow's own model when resuming, because the screens
            // ahead read them from there and nothing else refills it — `OnboardingModel` is
            // rebuilt empty every launch, and the only reason these screens had names the first
            // time is that the person had just typed them.
            //
            // Without this the screen resuming lands on is titled "Connect with  💞", and the
            // reveal at the end calls them "You". Both were collected, both were saved, and both
            // are already in `appModel.couple` — adopted by `loadSignedInState` before routing
            // here. Only the placeholders are skipped: `fetchOwnProfile` substitutes "You" for an
            // empty name, and an unpaired couple's partner is "Partner", neither of which is worth
            // copying over a blank.
            if appModel.hasSavedOnboardingProgress {
                let myName = appModel.couple.partnerA.name
                if !myName.isEmpty, myName != "You" { onboarding.firstName = myName }
                let theirName = appModel.couple.partnerB.name
                if !theirName.isEmpty, theirName != "Partner" { onboarding.partnerName = theirName }
            }
        }
        .onOpenURL { url in
            // Google's sign-in flow redirects back into the app via its own URL scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            if Self.isPasswordRecoveryLink(url) {
                Task { await handlePasswordRecovery(url) }
                return
            }
            guard let code = InviteCode.code(from: url) else { return }
            onboarding.resetForNewInvite(code: code)
        }
        .fullScreenCover(isPresented: $showingPasswordReset) {
            ResetPasswordView()
        }
        // Not on WelcomeView, where `accountDeletedMessage` lives: an account that has just been
        // created has `needsOnboarding` set, so the stack's root is the first onboarding question
        // and WelcomeView is never shown. This is the one container both roots share.
        .alert("We've started a new account", isPresented: Binding(
            get: { appModel.signedInToNewAccountMessage != nil },
            set: { if !$0 { appModel.signedInToNewAccountMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appModel.signedInToNewAccountMessage ?? "")
        }
        .alert("Link expired", isPresented: Binding(get: { passwordRecoveryError != nil }, set: { if !$0 { passwordRecoveryError = nil } })) {
            Button("OK") {}
        } message: {
            Text(passwordRecoveryError ?? "This password reset link is no longer valid — request a new one from the sign-in screen.")
        }
    }

    /// What leaving actually costs here — which is less than it first looked.
    ///
    /// Not "you'll lose your progress". This is question one, and `onboarding` is `@State` on this
    /// view, so it is built fresh on every launch: somebody who relaunched into this screen has an
    /// empty `OnboardingModel`, and somebody who walked back to it is starting over regardless.
    /// There are no answers here to lose. Warning about them describes a loss that does not
    /// happen, and the answers it would be naming — situation, frequency, goals, names,
    /// anniversary — are not what anyone fears losing anyway. Notification permission is not in
    /// this set at all: that is granted to iOS at the system prompt and outlives every bit of this.
    ///
    /// What is genuinely worth saying is that the account already exists, because the flow creates
    /// it part-way through at `.saveAccount`. Without that sentence the natural move on returning
    /// is "Get started", the same address, and a "this email is already taken" wall.
    ///
    /// The no-account variant has no audience on this screen — it is the root of the *resuming*
    /// flow, which `loadSignedInState` reaches only when a session exists, and a session means an
    /// account. It is kept because the sentence is keyed to the fact rather than to the screen,
    /// and the fresh flow's own back-out, where both are live, should use this same dialog.
    private var exitConfirmationMessage: String {
        BackendService.currentUserID != nil
            ? "Your account is already created — use Sign in to come back to it."
            : "You haven't created an account yet, so nothing is saved."
    }

    /// Recognises both shapes a recovery link can arrive in.
    ///
    /// The https one is what `requestPasswordReset` now asks for — a Universal Link, so iOS opens
    /// the app rather than Safari. The custom scheme is the one it used to ask for, and is still
    /// accepted because it is not ours to retire: links already sitting in inboxes carry it, and
    /// so do builds people have installed and not yet updated. Dropping it would break password
    /// reset for exactly the users least able to work out why.
    static func isPasswordRecoveryLink(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "twofold", url.host?.lowercased() == "reset-password" {
            return true
        }
        guard url.scheme?.lowercased() == "https" else { return false }
        // Path only — the host is whatever the associated-domains entitlement already let through,
        // and matching on it as well would mean a second place to update if the domain ever moves.
        // `pathComponents` rather than `path` for the same reason InviteCode uses it: it drops the
        // separators, so a trailing slash does not change the answer.
        let components = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        return components == ["auth", "reset-password"]
    }

    /// `ForgotPasswordView`'s emailed link lands here already tapped-through from Supabase's own
    /// domain (which verified the token server-side) — exchanging it for a session is what
    /// `completePasswordRecovery` does; a failure here means an expired/already-used/malformed
    /// link, not a network hiccup worth silently retrying.
    private func handlePasswordRecovery(_ url: URL) async {
        do {
            try await BackendService.completePasswordRecovery(from: url)
            showingPasswordReset = true
        } catch {
            // Deliberately not `error.localizedDescription`.
            //
            // Under the SDK's PKCE flow a failed exchange throws `pkceGrantCodeExchange(message:)`
            // whose message is the URL's own `error_description`, verbatim. The URL comes from
            // whoever opened it — any installed app can fire `twofold://reset-password` with no
            // prompt — so that put an attacker's sentence inside a native alert titled by us:
            // "Your Twofold account is locked, call support on …". Percent-decoding means they get
            // punctuation and newlines too.
            //
            // There is nothing here worth showing that the static copy does not already say. A
            // recovery link either works or has expired, and both readings are the same sentence.
            passwordRecoveryError = "This password reset link is no longer valid — request a new one from the sign-in screen."
        }
    }

    @ViewBuilder
    private func destination(for step: OnboardingStep) -> some View {
        switch step {
        case .situation:
            RelationshipSituationView()
        case .frequency:
            FrequencyView()
        case .attribution:
            AttributionView()
        case .goals:
            GoalsView()
        case .yourName:
            YourNameView()
        case .partnerName:
            PartnerNameView()
        case .gender:
            GenderView()
        case .coupleLocations:
            CoupleLocationsView()
        case .anniversaryDate:
            AnniversaryDateView()
        case .happyAnniversary:
            let years: Int = {
                guard let anniversaryDate = onboarding.anniversaryDate else { return 0 }
                return max(0, Calendar.current.dateComponents([.year], from: anniversaryDate, to: .now).year ?? 0)
            }()
            HappyAnniversaryView(years: years) {
                // Same sameCity check AnniversaryDateView itself uses to pick between these two.
                let sameCity: Bool = {
                    guard let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return false }
                    return mine.city == theirs.city && mine.country == theirs.country
                }()
                // Memory screens now come before the notification/Live Activity sell screens.
                onboarding.path.append(sameCity ? .memoriesSell : .personalizedInsight)
            }
        case .personalizedInsight:
            PersonalizedInsightView()
        case .notificationsSell:
            NotificationsSellView()
        case .liveActivitySell:
            LiveActivitySellView()
        case .memoriesSell:
            MemoriesSellView()
        case .mapSell:
            MapSellView()
        case .invitePartner:
            InvitePartnerView()
        case .firstMemoryIntro:
            FirstMemoryIntroView()
        case .firstMemory:
            FirstMemoryView()
        case .twofoldPreview:
            TwofoldPreviewView()
        case .trialTrust:
            TrialTrustView()
        case .paywall:
            // isDismissable: false — this is pushed onto the onboarding path, not sheeted, so
            // there's nothing to dismiss to. Without this, `PaywallView.handleEntitlementChange`
            // would call `dismiss()` right after `onSubscribed()` appends `.purchaseSuccess`,
            // popping both it and this screen off `onboarding.path` in the same run-loop turn —
            // the white screen bug this comment is here to prevent regressing.
            PaywallView(onSubscribed: { onboarding.path.append(.purchaseSuccess) }, isDismissable: false)
        case .purchaseSuccess:
            PurchaseSuccessView()
        case .saveAccount:
            SaveAccountView()
        case .createAccount:
            CreateAccountView()
        case .homeCity:
            HomeCityView()
        case .addPhoto:
            AddPhotoView()
        case .connectPartner:
            ConnectPartnerView()
        case .shareInvite:
            ShareInviteView(onboarding: onboarding)
        case .enterPartnerCode:
            EnterPartnerCodeView()
        case .joinInvite:
            JoinInviteView()
        case .connectionRequestSent:
            ConnectionRequestSentView(
                inviterName: onboarding.inviterName ?? "your partner",
                selfPhotoData: onboarding.selfPhotoData
            ) {
                onboarding.path.append(.nextTrip)
            }
        case .nextTrip:
            NextTripView()
        case .addTripDetails:
            AddTripDetailsView(
                mode: .onboarding,
                partnerName: onboarding.inviterName ?? "Partner",
                onSave: { trip in
                    onboarding.draftedTrip = trip
                    onboarding.path.append(.reveal)
                }
            )
        case .reveal:
            OnboardingRevealView()
        }
    }
}

#Preview {
    OnboardingCoordinatorView()
        .environment(AppModel())
}
