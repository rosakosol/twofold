//
//  YourNameView.swift
//  Twofold
//

import SwiftUI

struct YourNameView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var name: String = ""
    @State private var errorMessage: String?

    var body: some View {
        OnboardingScaffold(
            title: "What's your name?",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageData: onboarding.selfPhotoData) { data in
                        onboarding.selfPhotoData = data
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TextField("Your name", text: $name)
                            .textContentType(.givenName)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .onChange(of: name) { _, _ in errorMessage = nil }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRed)
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: validateAndContinue,
            primaryDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty
        )
        .onAppear { name = onboarding.firstName }
    }

    private func validateAndContinue() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let structuralError = NameValidator.structuralError(for: trimmed) {
            errorMessage = structuralError
            return
        }

        guard !NameValidator.isInappropriate(trimmed) else {
            errorMessage = "Please enter an appropriate name."
            return
        }

        errorMessage = nil
        onboarding.firstName = trimmed
        onboarding.path.append(.partnerName)
    }
}

#Preview {
    NavigationStack {
        YourNameView()
    }
    .environment(OnboardingModel())
}
