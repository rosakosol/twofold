//
//  HomeCitiesView.swift
//  Twofold
//
//  Progressive home-card sheet for setting your home city. Your partner's city can only be
//  set from their own signed-in session — RLS blocks writing another profile's row — so
//  their picker here is read-only, showing whatever they've set (or a "not set yet" hint).
//

import SwiftUI

struct HomeCitiesView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var mine: Place?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            OnboardingScaffold(
                title: "Set your home cities",
                subtitle: "This is how we calculate the distance between you two.",
                content: {
                    VStack(spacing: Theme.Spacing.md) {
                        CityMenuPicker(label: "Your city", selection: $mine)
                        CityMenuPicker(label: "\(appModel.partner.name)'s city", selection: .constant(appModel.partner.homeCity), placeholder: "Not set yet")
                            .disabled(true)
                    }
                },
                primaryTitle: "Save",
                primaryAction: save,
                primaryDisabled: mine == nil || isSaving
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                mine = appModel.currentUser.homeCity
            }
        }
    }

    private func save() {
        guard let mine else { return }
        isSaving = true
        Task {
            await appModel.setHomeCity(for: appModel.currentUser.id, city: mine)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    HomeCitiesView()
        .environment(AppModel())
}
