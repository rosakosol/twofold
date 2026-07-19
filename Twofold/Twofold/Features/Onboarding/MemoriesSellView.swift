//
//  MemoriesSellView.swift
//  Twofold
//
//  Feature-education screen, same idea as LiveActivitySellView/WidgetSellView — mock `Memory`
//  values rendered through the real row layout from `MemoriesListView`, using real bundled
//  photos (`OnboardingMemoryImage`, keyed by the same `photoSeed` `MapSellView`'s pins use)
//  instead of a placeholder, so the row actually looks like a populated memory rather than an
//  empty one. Comes right before MapSellView, which pitches the same feature's map view.
//

import SwiftUI

struct MemoriesSellView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var entriesVisible: Set<Int> = []

    private var mockMemories: [Memory] {
        let calendar = Calendar.current
        return [
            Memory(title: "That sunset", place: onboarding.homeCity, date: calendar.date(byAdding: .day, value: -23, to: .now) ?? .now, note: "Save the moments that make the distance worth it.", photoSeed: 0),
            Memory(title: "First trip together", place: onboarding.partnerCity, date: calendar.date(byAdding: .month, value: -2, to: .now) ?? .now, note: "Every reunion, kept somewhere safe.", photoSeed: 1),
            Memory(title: "Where we met", place: onboarding.homeCity, date: calendar.date(byAdding: .month, value: -4, to: .now) ?? .now, note: "The place it all started.", photoSeed: 2),
        ]
    }

    var body: some View {
        OnboardingScaffold(
            title: "Save your memories forever 💛",
            subtitle: "Keep photos and moments from your time together, whenever they happen.",
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    ForEach(Array(mockMemories.enumerated()), id: \.offset) { index, memory in
                        memoryRow(memory)
                            .opacity(entriesVisible.contains(index) ? 1 : 0)
                            .offset(x: entriesVisible.contains(index) ? 0 : -16)
                    }
                }
                .onAppear {
                    for index in mockMemories.indices {
                        withAnimation(.easeOut(duration: 0.4).delay(0.1 + Double(index) * 0.15)) {
                            _ = entriesVisible.insert(index)
                        }
                    }
                }
            },
            primaryTitle: "Continue",
            primaryAction: { onboarding.path.append(.mapSell) }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: entriesVisible)
    }

    /// Same structure as `MemoriesListView.memoryRow` — kept in lockstep with the real feature.
    private func memoryRow(_ memory: Memory) -> some View {
        SectionCard {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                OnboardingMemoryImage(seed: memory.photoSeed, cornerRadius: 14)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    if let place = memory.place {
                        Text(place.city)
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .lineLimit(1)
                    }
                    Text(memory.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                    if !memory.note.isEmpty {
                        Text(memory.note)
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.trailing, Theme.Spacing.md)
    }
}

#Preview {
    NavigationStack {
        MemoriesSellView()
    }
    .environment(OnboardingModel())
}
