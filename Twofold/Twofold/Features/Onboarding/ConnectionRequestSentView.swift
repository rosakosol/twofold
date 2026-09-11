//
//  ConnectionRequestSentView.swift
//  Twofold
//
//  Shown right after redeeming a partner's invite code during onboarding — reused by both entry
//  points that can redeem mid-onboarding (EnterPartnerCodeView's already-has-an-account branch,
//  and HomeCityView's invitee branch via AddPhotoView). Same "decoupled, caller decides what's
//  next" shape `HappyAnniversaryView` uses.
//
//  Replaces the old ConnectedRevealView ("You're connected!") — redeeming only ever creates a
//  pending request now (double verification: the inviter still has to accept it), so celebrating
//  an actual connection here would be premature. `RootView`'s own `PartnerConnectedView` is the
//  one real celebration moment now, for whichever side is using the app when the request is
//  actually accepted.
//

import SwiftUI

struct ConnectionRequestSentView: View {
    var inviterName: String
    /// The photo this person picked a screen or two ago, still raw JPEG — there is no session to
    /// have uploaded it against yet, so it lives on `OnboardingModel` until account creation.
    var selfPhotoData: Data? = nil
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            // Their own face, not the inviter's.
            //
            // This screen used to show the inviter, which sounds right — they are who we are
            // waiting on — but the invite flow reaches here having never reliably had a photo for
            // them: `inviterAvatarURL` comes from an unauthenticated lookup that is often empty,
            // so most people met a grey circle with someone else's initial in it.
            //
            // What the invitee does have is the photo they chose about a minute ago, and showing
            // it says the true thing about this moment: this is what has been sent, and it is on
            // its way. When they skipped that step there is no face to show at all, so the brand
            // beats instead of a placeholder standing in for a person.
            if let selfPhotoData, let image = UIImage(data: selfPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Theme.skyBlue.opacity(0.6), lineWidth: 2))
                    .accessibilityLabel("Your photo")
            } else {
                PulsingGlobeHeart(size: 72, showsGlow: false)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Text("Request sent")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("\(inviterName) needs to accept before you're connected — we'll let you know.")
                    .font(.body)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer()

            Button(action: onContinue) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

#Preview("No photo picked") {
    NavigationStack {
        ConnectionRequestSentView(inviterName: "Alex", onContinue: {})
    }
}
