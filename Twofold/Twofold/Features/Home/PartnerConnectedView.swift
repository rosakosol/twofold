//
//  PartnerConnectedView.swift
//  Twofold
//
//  Full-screen celebration shown the moment `AppModel.partnerConnected` flips from false to
//  true anywhere post-onboarding — whether the signed-in user just redeemed a code themselves,
//  or a background refresh discovers their partner redeemed one while this device was away.
//  Onboarding has its own, more modest ConnectedRevealView as part of that flow; this is the
//  bigger, "It's a match"-style moment for everyone else. Reuses ConfettiBurstView (also used
//  by onboarding's TwofoldPreviewView) rather than inventing a second celebration effect.
//

import SwiftUI

struct PartnerConnectedView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var didCelebrate = false
    @State private var avatarsAppeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                HStack(spacing: -28) {
                    AvatarView(person: appModel.currentUser, size: 128, showsRing: true)
                        .rotationEffect(.degrees(-6))
                        .offset(x: avatarsAppeared ? 0 : -100, y: avatarsAppeared ? 0 : -20)
                    AvatarView(person: appModel.partner, size: 128, showsRing: true)
                        .rotationEffect(.degrees(6))
                        .offset(x: avatarsAppeared ? 0 : 100, y: avatarsAppeared ? 0 : -20)
                }
                .opacity(avatarsAppeared ? 1 : 0)

                ZStack {
                    Circle().fill(Theme.heartRed)
                    Image(systemName: "heart.fill").foregroundStyle(.white).font(.title3)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .scaleEffect(avatarsAppeared ? 1 : 0)
                .offset(y: 44)

                ConfettiBurstView(trigger: didCelebrate)
            }
            .frame(height: 180)

            VStack(spacing: Theme.Spacing.xs) {
                Text("You're connected!")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(appModel.currentUser.name) & \(appModel.partner.name) are now sharing Twofold together.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Let's go")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.primaryButtonGradient, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                avatarsAppeared = true
            }
            didCelebrate = true
        }
        .sensoryFeedback(.success, trigger: didCelebrate)
    }
}

#Preview {
    PartnerConnectedView()
        .environment(AppModel())
}
