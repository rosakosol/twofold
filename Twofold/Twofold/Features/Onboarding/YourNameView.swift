//
//  YourNameView.swift
//  Twofold
//

import SwiftUI

struct YourNameView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var name: String = ""
    @State private var errorMessage: String?
    @State private var isValidating = false

    var body: some View {
        OnboardingScaffold(
            title: "What should we call you?",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageData: onboarding.selfPhotoData) { data in
                        onboarding.selfPhotoData = data
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TextField("First name", text: $name)
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
            primaryDisabled: isValidating || name.trimmingCharacters(in: .whitespaces).isEmpty,
            primaryLoading: isValidating
        )
        .onAppear { name = onboarding.firstName }
    }

    private func validateAndContinue() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let structuralError = NameValidator.structuralError(for: trimmed) {
            errorMessage = structuralError
            return
        }

        errorMessage = nil
        isValidating = true
        Task {
            let offensive = await NameModerationService.isOffensive(trimmed)
            isValidating = false
            guard !offensive else {
                errorMessage = "Please enter an appropriate name."
                return
            }
            onboarding.firstName = trimmed
            onboarding.path.append(.partnerName)
        }
    }
}

#Preview {
    NavigationStack {
        YourNameView()
    }
    .environment(OnboardingModel())
}
