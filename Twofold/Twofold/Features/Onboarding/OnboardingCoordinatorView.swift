//
//  OnboardingCoordinatorView.swift
//  Twofold
//

import SwiftUI
import GoogleSignIn
import PostHog

struct OnboardingCoordinatorView: View {
    @State private var onboarding = OnboardingModel()
    @State private var showingPasswordReset = false
    @State private var passwordRecoveryError: String?

    var body: some View {
        NavigationStack(path: $onboarding.path) {
            WelcomeView()
                .postHogScreenView("Onboarding: Welcome")
                .navigationDestination(for: OnboardingStep.self) { step in
                    destination(for: step)
                        .postHogScreenView(step.analyticsName)
                }
        }
        .environment(onboarding)
        .onOpenURL { url in
            // Google's sign-in flow redirects back into the app via its own URL scheme.
            if GIDSignIn.sharedInstance.handle(url) { return }
            if url.scheme?.lowercased() == "twofold", url.host?.lowercased() == "reset-password" {
                Task { await handlePasswordRecovery(url) }
                return
            }
            guard let code = InviteCode.code(from: url) else { return }
            onboarding.resetForNewInvite(code: code)
        }
        .fullScreenCover(isPresented: $showingPasswordReset) {
            ResetPasswordView()
        }
        .alert("Link expired", isPresented: Binding(get: { passwordRecoveryError != nil }, set: { if !$0 { passwordRecoveryError = nil } })) {
            Button("OK") {}
        } message: {
            Text(passwordRecoveryError ?? "This password reset link is no longer valid — request a new one from the sign-in screen.")
        }
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
            passwordRecoveryError = error.localizedDescription
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
                onboarding.path.append(sameCity ? .notificationsSell : .personalizedInsight)
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
            ConnectionRequestSentView(inviterName: onboarding.inviterName ?? "your partner", inviterAvatarURL: onboarding.inviterAvatarURL) {
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
