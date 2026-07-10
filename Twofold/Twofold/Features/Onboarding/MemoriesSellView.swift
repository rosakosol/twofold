//
//  MemoriesSellView.swift
//  Twofold
//
//  Feature-education screen, same idea as LiveActivitySellView/WidgetSellView — a scrollable
//  journal/timeline mockup (matching AddMemoryView's real emoji set) rather than fabricated
//  photos. Comes right before MapSellView, which pitches the same feature's map view.
//

import SwiftUI

struct MemoriesSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var entriesVisible: Set<Int> = []

    private struct JournalEntry {
        let dateLabel: String
        let emoji: String
        let title: String
        let body: String
    }

    private let entries: [JournalEntry] = [
        JournalEntry(dateLabel: "JUN\n20", emoji: "🌅", title: "That sunset", body: "Save the moments that make the distance worth it."),
        JournalEntry(dateLabel: "MAY\n04", emoji: "✈️", title: "First trip together", body: "Every reunion, kept somewhere safe."),
        JournalEntry(dateLabel: "MAR\n12", emoji: "💛", title: "Where we met", body: "The place it all started."),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "Every memory, saved forever 💛",
            subtitle: "Keep photos and moments from your time together, whenever they happen.",
            content: {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        journalRow(entry, isLast: index == entries.count - 1)
                            .opacity(entriesVisible.contains(index) ? 1 : 0)
                            .offset(x: entriesVisible.contains(index) ? 0 : -16)
                    }
                }
                .onAppear {
                    for index in entries.indices {
                        withAnimation(.easeOut(duration: 0.4).delay(0.1 + Double(index) * 0.15)) {
                            _ = entriesVisible.insert(index)
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.mapSell) }
        )
    }

    private func journalRow(_ entry: JournalEntry, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(spacing: Theme.Spacing.xs) {
                Text(entry.dateLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                if !isLast {
                    Rectangle()
                        .fill(Theme.subtleInk.opacity(0.2))
                        .frame(width: 2)
                        .frame(minHeight: Theme.Spacing.xl)
                }
            }

            SectionCard {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Text(entry.emoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.subheadline.weight(.semibold))
                        Text(entry.body).font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.bottom, Theme.Spacing.md)
        }
    }
}

#Preview {
    NavigationStack {
        MemoriesSellView()
    }
    .environment(OnboardingModel())
}
