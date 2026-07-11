//
//  FirstMemoryView.swift
//  Twofold
//
//  Shown only when onboarding's "add your first flight" step was skipped (or couldn't add
//  one) — gives that moment somewhere to land besides an empty preview screen. Defaults the
//  memory's place to the user's own home city so this stays a single quick field, not a full
//  add-memory form.
//

import SwiftUI

struct FirstMemoryView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(AppModel.self) private var appModel
    @State private var title = ""
    @State private var note = ""
    @State private var isSaving = false

    var body: some View {
        OnboardingScaffold(
            title: "Save your first memory 💛",
            subtitle: "A moment, a place, a feeling — you can always add more later.",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    TextField("Memory title", text: $title)
                        .font(.title3.weight(.semibold))
                        .padding()
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    TextField("Write a few words about this memory", text: $note, axis: .vertical)
                        .lineLimit(4...8)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
            },
            primaryTitle: "Save memory",
            primaryAction: save,
            primaryDisabled: title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving,
            secondaryTitle: "Add this later",
            secondaryAction: { onboarding.path.append(.twofoldPreview) }
        )
    }

    private func save() {
        let place = onboarding.homeCity ?? onboarding.partnerCity
        isSaving = true
        Task {
            await appModel.addMemory(
                title: title.trimmingCharacters(in: .whitespaces),
                place: place,
                date: .now,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                imagesData: []
            )
            isSaving = false
            onboarding.path.append(.twofoldPreview)
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
