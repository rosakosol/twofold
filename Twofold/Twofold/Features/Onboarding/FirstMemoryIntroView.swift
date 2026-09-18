//
//  FirstMemoryIntroView.swift
//  Twofold
//
//  A short beat between MapSellView's feature pitch and the real `FirstMemoryView` action
//  screen — makes the ask ("add your first memory, right now") explicit and gives it some
//  motivating weight before handing off to the actual add-a-memory sheet.
//
//  The body copy comes from Devasia et al. (DIS '25), a diary + interview study of 13 long-distance
//  couples: "[d]ue to the lack of functional memory saving, several participants expressed that they
//  save special memories manually", screenshotting the screen with their phones or keeping a Discord
//  channel "dedicated to quotes and screenshots and special moments". One participant's Steam
//  screenshots were "just so hard to find". That is the gap a first saved memory here fills, so it
//  leads. The second source is a 2025 evaluation of Paired, kept for the outcome evidence.
//

import SwiftUI

struct FirstMemoryIntroView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @Environment(\.openURL) private var openURL

    private struct RelationshipSource: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let detail: String
        let url: URL
    }

    private let bodyText = "Researchers who studied long-distance couples in 2025 found they hang onto screenshots and photos of the moments they shared \u{2014} and that the games they play together give them almost nowhere to keep them. This is that place. Start with one."

    private let sources: [RelationshipSource] = [
        RelationshipSource(
            icon: "doc.text.fill",
            name: "Devasia et al., DIS '25",
            detail: "Partnership through Play: How Long-Distance Couples Use Digital Games to Facilitate Intimacy",
            url: URL(string: "https://doi.org/10.1145/3715336.3735773")!
        ),
        RelationshipSource(
            icon: "book.closed.fill",
            name: "JMIR mHealth and uHealth",
            detail: "Exploring the Potential of a Digital Intervention to Enhance Couple Relationships (2025)",
            url: URL(string: "https://mhealth.jmir.org/2025/1/e55433")!
        ),
    ]

    var body: some View {
        // YourNameView requires a non-empty name before you can advance, so by the time any
        // later onboarding screen runs (this one included), this is always the real name — no
        // fallback needed.
        OnboardingScaffold(
            title: "\(onboarding.firstName), let's add your first memory",
            subtitle: bodyText,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    // Says what the screen is about before the words do. Modest at 40pt — this
                    // screen also carries a long paragraph and two source cards, and the celebration
                    // sizes belong on the screens that are actually celebrating something.
                    Text("📸")
                        .font(.system(size: 40))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ForEach(sources) { source in
                            sourceCard(source)
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.firstMemory) }
        )
    }

    private func sourceCard(_ source: RelationshipSource) -> some View {
        Button {
            openURL(source.url)
        } label: {
            SectionCard {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: source.icon)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(source.detail)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        FirstMemoryIntroView()
    }
    .environment(OnboardingModel())
}
