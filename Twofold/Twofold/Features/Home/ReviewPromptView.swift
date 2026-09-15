//
//  ReviewPromptView.swift
//  Twofold
//
//  Custom ask shown before the system review prompt — Apple gives no way to know whether
//  someone actually left a review, so this is what "until they leave a review" is built on:
//  saying yes here both fires `AppStore.requestReview` and permanently stops future prompts
//  (see ReviewPromptService); saying "Not Right Now" only dismisses this one, leaving the next
//  distinct milestone free to ask again.
//

import StoreKit
import SwiftUI

private extension ReviewMilestone {
    var celebratoryLine: String {
        switch self {
        case .partnerConnected: "You're all set up together!"
        case .firstFlight: "You just added your first flight!"
        case .firstTrip: "You just added your first trip!"
        case .firstMemory: "You just saved your first memory!"
        case .firstGameResults: "You just finished your first game together!"
        }
    }
}

extension ReviewMilestone: Identifiable {
    var id: String { rawValue }
}

struct ReviewPromptView: View {
    let milestone: ReviewMilestone

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Spacers rather than top/bottom padding, so the content sits in the middle of whatever
            // height the detent gives it instead of at a fixed distance from the top. With padding
            // it was centred only when the content happened to add up to the detent.
            Spacer(minLength: 0)

            Text("🎉").font(.system(size: 48))

            VStack(spacing: Theme.Spacing.xs) {
                Text(milestone.celebratoryLine)
                    .font(.headline)
                Text("Enjoying Twofold so far?")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                Button {
                    ReviewPromptService.markRespondedPositively()
                    requestReview()
                    dismiss()
                } label: {
                    Text("Yes, Rate Twofold!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)

                Button("Not Right Now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.lg)
        // `maxHeight: .infinity` is the fix. The stack sized itself to its content while the sheet
        // was pinned at 300pt, so `.background` painted the content's height and the rest of the
        // sheet was left bare — the gradient appeared cropped top and bottom because it was never
        // drawn there. Filling the frame first gives the background the whole sheet to cover.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        AppStore.requestReview(in: scene)
    }
}

#Preview {
    ReviewPromptView(milestone: .firstMemory)
}
