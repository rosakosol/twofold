//
//  PartnerNameView.swift
//  Twofold
//
//  Personalization only — not a real linked account. Real partner pairing still happens
//  via the existing invite-code flow, later, from the home screen's setup checklist. The
//  photo picked here is just this user's placeholder guess of their partner's photo; once
//  the partner actually joins and sets their own, that takes over automatically.
//

import SwiftUI

struct PartnerNameView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var name: String = ""
    @State private var errorMessage: String?

    var body: some View {
        OnboardingScaffold(
            title: "And your partner?",
            centered: true,
            content: {
                VStack(spacing: Theme.Spacing.lg) {
                    RoundPhotoPicker(placeholderSystemImage: "person.fill", initialImageData: onboarding.partnerPhotoData) { data in
                        onboarding.partnerPhotoData = data
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TextField("Their first name", text: $name)
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
        .onAppear { name = onboarding.partnerName }
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
        onboarding.partnerName = trimmed
        onboarding.path.append(.gender)
    }
}

#Preview {
    NavigationStack {
        PartnerNameView()
    }
    .environment(OnboardingModel())
}
