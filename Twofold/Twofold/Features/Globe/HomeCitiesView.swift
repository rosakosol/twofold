//
//  HomeCitiesView.swift
//  Twofold
//
//  Progressive home-card sheet for setting both partners' home cities. Your own city
//  may already be set from onboarding; your partner's stays unset in this backend-less
//  demo until they'd complete their own onboarding on their own device, so this screen
//  doubles as a stand-in for "set it on their behalf" for demo purposes.
//

import SwiftUI

struct HomeCitiesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var mine: Place?
    @State private var partners: Place?

    var body: some View {
        NavigationStack {
            OnboardingScaffold(
                title: "Set your home cities",
                subtitle: "This is how we calculate the distance between you two.",
                content: {
                    VStack(spacing: Theme.Spacing.md) {
                        CityMenuPicker(label: "Your city", selection: $mine)
                        CityMenuPicker(label: "\(appModel.partner.name)'s city", selection: $partners)
                    }
                },
                primaryTitle: "Save",
                primaryAction: save,
                primaryDisabled: mine == nil && partners == nil
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                mine = appModel.currentUser.homeCity
                partners = appModel.partner.homeCity
            }
        }
    }

    private func save() {
        if let mine { appModel.setHomeCity(for: appModel.currentUser.id, city: mine) }
        if let partners { appModel.setHomeCity(for: appModel.partner.id, city: partners) }
        dismiss()
    }
}

#Preview {
    HomeCitiesView()
        .environment(AppModel())
}
