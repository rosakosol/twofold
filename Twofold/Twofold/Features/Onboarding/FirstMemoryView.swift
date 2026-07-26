//
//  FirstMemoryView.swift
//  Twofold
//
//  Thin sheet-wrapper around the real `AddMemoryView` — same shape onboarding's old
//  AddFirstFlightView used for `AddFlightFlowView`. `AddMemoryView` owns its own
//  NavigationStack, so it must be sheet-presented rather than pushed directly onto
//  onboarding's NavigationStack (pushing a view that owns its own stack crashes with
//  AnyNavigationPath.Error.comparisonTypeMismatch).
//
//  `isDismissable: false` — no swipe-to-dismiss and no Cancel button, unlike every other
//  `AddMemoryView` call site (both would leave onboarding with nowhere to go, since nothing
//  else here advances `onboarding.path`). Still skippable, though: `AddMemoryView`'s own
//  bottomBar shows a text-only Skip button whenever `isDismissable` is false, which just calls
//  `dismiss()` with nothing saved. `onDismiss` below fires either way — real save or Skip — so
//  onboarding always advances once this sheet closes, whether or not a memory actually exists.
//

import SwiftUI

struct FirstMemoryView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var showingForm = false

    var body: some View {
        Theme.backgroundGradient
            .ignoresSafeArea()
            .onAppear { showingForm = true }
            .sheet(isPresented: $showingForm, onDismiss: {
                // Notification/Live Activity sell screens now follow the memory screens —
                // fires identically whether the sheet closed via a real save or the new
                // Skip button (see `AddMemoryView`'s `bottomBar`).
                onboarding.path.append(.notificationsSell)
            }) {
                AddMemoryView(isDismissable: false)
            }
    }
}

#Preview {
    NavigationStack {
        FirstMemoryView()
    }
    .environment(OnboardingModel())
    .environment(AppModel())
}
