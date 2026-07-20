//
//  FirstMemoryIntroView.swift
//  Twofold
//
//  A short beat between MapSellView's feature pitch and the real `FirstMemoryView` action
//  screen — makes the ask ("add your first memory, right now") explicit and gives it some
//  motivating weight before handing off to the actual add-a-memory sheet.
//
//  The stat and its "sources" below are placeholder copy — deliberately generic rather than
//  naming any real journal/study, since there isn't a real citation behind them yet. Swap
//  `statText` and `sources` for the real thing once there's real research to cite.
//

import SwiftUI

struct FirstMemoryIntroView: View {
    @Environment(OnboardingModel.self) private var onboarding

    private struct PlaceholderSource: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
    }

    private let statText = "Couples that stay connected digitally with small touches — like saving shared trips and memories — are found to have 47% stronger relationship satisfaction, even across the distance."

    private let sources: [PlaceholderSource] = [
        PlaceholderSource(icon: "book.closed.fill", name: "Journal of Relationship Psychology"),
        PlaceholderSource(icon: "doc.text.fill", name: "Digital Connection & Wellbeing Study"),
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

    private func sourceCard(_ source: PlaceholderSource) -> some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: source.icon)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                Text(source.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
                Spacer(minLength: 0)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FirstMemoryIntroView()
    }
    .environment(OnboardingModel())
}
