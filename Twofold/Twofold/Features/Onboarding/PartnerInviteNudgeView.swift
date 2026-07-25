//
//  PartnerInviteNudgeView.swift
//  Twofold
//
//  Shown at most once a day, right after a solo user finishes adding a trip/memory or playing a
//  game — see `AppModel.noteSoloActionCompleted()`/`PartnerInviteNudgeService`. Deliberately
//  light-touch (a dismissable sheet, not a gate) since these flows already work fully solo now;
//  this is a suggestion, not a requirement. Reuses `PartnerConnectCard`, the same "share my
//  code / enter theirs" UI every other connect entry point in the app already uses.
//

import SwiftUI

struct PartnerInviteNudgeView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("💌").font(.system(size: 48))
                    Text("Nice work!")
                        .font(.title2.weight(.bold))
                    Text("Twofold is even better shared. Invite your partner to see everything together.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
                .padding(.top, Theme.Spacing.lg)

                PartnerConnectCard(
                    inviteCode: Binding(get: { appModel.inviteCode }, set: { appModel.inviteCode = $0 }),
                    onRedeemSuccess: { dismiss() }
                )

                Spacer()
            }
            .padding(Theme.Spacing.md)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PartnerInviteNudgeView()
        .environment(AppModel())
}
