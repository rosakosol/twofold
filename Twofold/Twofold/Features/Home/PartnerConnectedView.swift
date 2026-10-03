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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            ZStack {
                HStack(spacing: -34) {
                    AvatarView(person: appModel.currentUser, size: 150, showsRing: true)
                        .rotationEffect(.degrees(-6))
                        .offset(x: avatarsAppeared ? 0 : -100, y: avatarsAppeared ? 0 : -20)
                    AvatarView(person: appModel.partner, size: 150, showsRing: true)
                        .rotationEffect(.degrees(6))
                        .offset(x: avatarsAppeared ? 0 : 100, y: avatarsAppeared ? 0 : -20)
                }
                .opacity(avatarsAppeared ? 1 : 0)

                // The coral gradient heart badge where the two photos meet (section 6).
                ZStack {
                    Circle().fill(Theme.coralGradient)
                    Image(systemName: "heart.fill").foregroundStyle(Theme.onFill).font(.title2)
                }
                .frame(width: 48, height: 48)
                .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                .shadow(color: Theme.Shadow.color, radius: 8, y: 4)
                .scaleEffect(avatarsAppeared ? 1 : 0)
                .offset(y: 58)
                .accessibilityHidden(true)

                ConfettiBurstView(trigger: didCelebrate)
            }
            .frame(height: 210)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(appModel.currentUser.name) and \(appModel.partner.name)")

            VStack(spacing: Theme.Spacing.xs) {
                Text("You're connected")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(appModel.currentUser.name) and \(appModel.partner.name) are now sharing Twofold together.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)
            }

            Spacer()
            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Let's go")
            }
            .buttonStyle(.twofoldPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(ScreenBackground())
        .interactiveDismissDisabled()
        .onAppear {
            if reduceMotion {
                avatarsAppeared = true
            } else {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                    avatarsAppeared = true
                }
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
