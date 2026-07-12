//
//  AddFlightStepScaffold.swift
//  Twofold
//
//  Shared chrome for each step of AddFlightFlowView's wizard — "Add Flight" title + a
//  per-step subtitle + content, plus the persistent top-bar cancel/skip button. Unlike
//  OnboardingScaffold's single pinned bottom bar, this flow needs a way out from any step
//  (not just the last one), so the button lives in the nav bar on every step instead.
//

import SwiftUI

struct AddFlightStepScaffold<Content: View>: View {
    let subtitle: String
    @ViewBuilder var content: Content

    @Environment(AddFlightFlowModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Add Flight")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }

                content
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(model.topBarTitle, action: model.onTopBarAction)
            }
        }
    }
}
