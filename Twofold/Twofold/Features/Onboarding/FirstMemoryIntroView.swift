//
//  FirstMemoryIntroView.swift
//  Twofold
//
//  A short beat between MapSellView's feature pitch and the real `FirstMemoryView` action
//  screen — makes the ask ("add your first memory, right now") explicit and gives it some
//  motivating weight before handing off to the actual add-a-memory sheet.
//
//  Both halves of the body copy are sourced, and each has one card below it.
//
//  "consistently report stronger relationships" is Majzoobi & Forstmeier's meta-analysis (14 studies):
//  reminiscing over relationship-defining memories correlates r = .334 with marital outcomes and
//  r = .445 with marital satisfaction. Correlational, so the sentence claims an association and not
//  a cause — happier couples reminiscing more fits that data just as well.
//
//  "came away measurably happier than they started" is the Remini study's pre/post PANAS positive
//  affect, which rose in both arms (32.67 -> 41.63 guided, 31.04 -> 35.46 baseline). Note that both
//  arms reminisced — the paper's own finding is that *structured* guidance beats unstructured, so
//  this screen leans only on the rise itself, which is the part both conditions share.
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

    private let bodyText = "Couples who revisit the memories they've made together consistently report stronger relationships \u{2014} and when a 2025 study sat partners down to actually do it, they came away measurably happier than they started. This is where yours go. Start with one."

    private let sources: [RelationshipSource] = [
        RelationshipSource(
            icon: "book.closed.fill",
            name: "Majzoobi & Forstmeier, 2022",
            detail: "Reminiscence of Relationship-Defining Memories and Marital Outcomes: A Meta-Analysis",
            url: URL(string: "https://doi.org/10.1111/jftr.12442")!
        ),
        RelationshipSource(
            icon: "doc.text.fill",
            name: "Jiang et al., CSCW 2025",
            detail: "Remini: Chatbot-Mediated Mutual Reminiscence Among Loved Ones",
            // arXiv rather than the ACM DOI (10.1145/3757650): same paper, and this one opens
            // for anyone who taps it instead of hitting the ACM paywall.
            url: URL(string: "https://arxiv.org/abs/2508.03355")!
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
