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
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Text("💌")
                .font(.system(size: 64))

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

#Preview {
    NavigationStack {
        ConnectionRequestSentView(inviterName: "Alex", onContinue: {})
    }
}
