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

import SwiftUI

struct FirstMemoryView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var showingForm = false

    var body: some View {
        Theme.backgroundGradient
            .ignoresSafeArea()
            .onAppear { showingForm = true }
            .sheet(isPresented: $showingForm, onDismiss: {
                onboarding.path.append(.twofoldPreview)
            }) {
                AddMemoryView()
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
