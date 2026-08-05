//
//  FirstMemoryIntroView.swift
//  Twofold
//
//  A short beat between MapSellView's feature pitch and the real `FirstMemoryView` action
//  screen — makes the ask ("add your first memory, right now") explicit and gives it some
//  motivating weight before handing off to the actual add-a-memory sheet.
//
//  The stat is from a 2025 mixed-methods evaluation of Paired, a relationship-focused app —
//  real evidence that regularly showing up for small, app-prompted moments together tracks with
//  measurably stronger relationships (see `sources` below). The second source is a 2025 HCI
//  study of long-distance couples that found "memories" was the relatedness need participants
//  most wished existing apps served — directly the gap a first saved memory here fills.
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

    private let statText = "In a 2025 study, couples who used a relationship-focused app for over three months reported relationship quality 35% higher than new users - and 64% said their relationship felt stronger since they started showing up for it together."

    private let sources: [RelationshipSource] = [
        RelationshipSource(
            icon: "book.closed.fill",
            name: "JMIR mHealth and uHealth",
            detail: "Exploring the Potential of a Digital Intervention to Enhance Couple Relationships (2025)",
            url: URL(string: "https://mhealth.jmir.org/2025/1/e55433")!
        ),
        RelationshipSource(
            icon: "doc.text.fill",
            name: "Devasia et al., DIS '25",
            detail: "Partnership through Play: How Long-Distance Couples Use Digital Games to Facilitate Intimacy",
            url: URL(string: "https://doi.org/10.1145/3715336.3735773")!
        ),
    ]

    var body: some View {
        // YourNameView requires a non-empty name before you can advance, so by the time any
        // later onboarding screen runs (this one included), this is always the real name — no
        // fallback needed.
        OnboardingScaffold(
            title: "\(onboarding.firstName), let's add your first memory",
            subtitle: statText,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(sources) { source in
                        sourceCard(source)
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
