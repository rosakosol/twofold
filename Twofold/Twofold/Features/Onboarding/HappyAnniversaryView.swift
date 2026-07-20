//
//  HappyAnniversaryView.swift
//  Twofold
//
//  Same-day-anniversary surprise — reused in two places: `AnniversaryDateView` pushes this
//  instead of straight to notificationsSell/personalizedInsight when the date just picked during
//  onboarding is today, and `AboutRelationshipView` (Settings' anniversary editor, reachable any
//  time post-onboarding) presents this as a full-screen cover on the same condition. Deliberately
//  has no dependency on `OnboardingModel` — `onContinue` is supplied by whichever caller knows
//  what "done" means for it (push further onboarding steps vs. just dismissing a settings sheet).
//

import SwiftUI

struct HappyAnniversaryView: View {
    /// Full years since the anniversary date, as computed by the caller (each already has the
    /// real `Date` in hand at the moment it decides to show this screen) — 0 for the literal
    /// "we started dating today" case, which gets its own copy below rather than "0 years."
    var years: Int
    var onContinue: () -> Void
    @State private var contentVisible = false

    private var subtitle: String {
        switch years {
        case ..<1: "Today's the day it all began. Here's to many more."
        case 1: "Here's to a year of love, and many more."
        default: "Here's to \(years) years of love, and many more."
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.heartRed, Color(hex: "FF8FA3")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            AnimatedHeartsView()

            VStack(spacing: Theme.Spacing.lg) {
                Spacer()

                Text("💕")
                    .font(.system(size: 64))
                    .scaleEffect(contentVisible ? 1 : 0.6)
                    .opacity(contentVisible ? 1 : 0)

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Happy Anniversary! 🎉")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)

                Spacer()

                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(.white, in: Capsule())
                .foregroundStyle(Theme.heartRed)
            }
            .padding(Theme.Spacing.lg)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                contentVisible = true
            }
        }
        .sensoryFeedback(.success, trigger: contentVisible)
    }
}

#Preview {
    NavigationStack {
        HappyAnniversaryView(years: 3, onContinue: {})
    }
}
