//
//  GenderView.swift
//  Twofold
//
//  Drives the possessive pronoun ("his"/"her"/a custom one) used in place of the generic
//  "their" on later screens — see `OnboardingModel.partnerPossessive`. Not persisted to
//  Supabase (no gender column exists), purely local personalization like the rest of this
//  flow's copy inputs.
//

import SwiftUI

struct GenderView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var userGender: Gender?
    @State private var partnerGender: Gender?

    // PartnerNameView requires a non-empty name before you can advance, so by the time any
    // later onboarding screen runs, this is always the real name — no fallback needed.
    private var partnerName: String { onboarding.partnerName }

    var body: some View {
        OnboardingScaffold(
            title: "A couple more details.",
            subtitle: "This helps us personalize how Twofold talks about you two.",
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    genderSection(title: "Your gender", selection: $userGender)
                    genderSection(title: "\(partnerName)'s gender", selection: $partnerGender)
                }
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.userGender = userGender
                onboarding.partnerGender = partnerGender
                onboarding.path.append(.benchmark)
            },
            primaryDisabled: userGender == nil || partnerGender == nil
        )
        .onAppear {
            userGender = onboarding.userGender
            partnerGender = onboarding.partnerGender
        }
    }

    private func genderSection(title: String, selection: Binding<Gender?>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Gender.allCases) { gender in
                    genderCard(gender, isSelected: selection.wrappedValue == gender) {
                        selection.wrappedValue = gender
                    }
                }
            }
        }
    }

    private func genderCard(_ gender: Gender, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(gender.emoji)
                    .font(.system(size: 32))
                Text(gender.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.skyBlue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        GenderView()
    }
    .environment({
        let model = OnboardingModel()
        model.partnerName = "Erin"
        return model
    }())
}
