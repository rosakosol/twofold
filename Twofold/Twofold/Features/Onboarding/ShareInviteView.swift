//
//  ShareInviteView.swift
//  Twofold
//
//  Used both as an onboarding step (pushed on the onboarding NavigationStack) and as a
//  standalone sheet from the home screen's "invite partner" checklist card, so it takes
//  its code and continue action as plain parameters instead of reading a specific model.
//

import SwiftUI

struct ShareInviteView: View {
    var code: String
    var onContinue: () -> Void

    init(code: String, onContinue: @escaping () -> Void) {
        self.code = code
        self.onContinue = onContinue
    }

    /// Convenience initializer for the onboarding NavigationStack destination, which reads
    /// its code from the shared `OnboardingModel` and advances to the next onboarding step.
    init(onboarding: OnboardingModel) {
        self.code = onboarding.inviteCode ?? InviteCode.generate(firstName: onboarding.firstName)
        self.onContinue = {
            onboarding.inviteCode = onboarding.inviteCode ?? InviteCode.generate(firstName: onboarding.firstName)
            onboarding.isPartnerConnected = true
            onboarding.path.append(.nextTrip)
        }
    }

    @State private var didCopy = false

    private var shareURL: URL { InviteCode.shareURL(for: code) }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.sm) {
                Text("Your code is")
                    .font(.headline)
                    .foregroundStyle(Theme.subtleInk)
                Text(code)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.skyBlue)
                Text("Share this with your partner so they can join you on Twofold.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                ShareLink(item: shareURL) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.skyBlue, in: Capsule())
                .foregroundStyle(.white)

                Button {
                    UIPasteboard.general.string = shareURL.absoluteString
                    didCopy = true
                } label: {
                    Label(didCopy ? "Copied!" : "Copy link", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.cardBackground, in: Capsule())
                .foregroundStyle(Theme.ink)

                Text("We'll let you know the moment they join.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)

                Button(action: onContinue) {
                    Text("Continue to Twofold")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.skyBlue)
                }
                .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ShareInviteView(code: "ROSA-4821", onContinue: {})
    }
}
