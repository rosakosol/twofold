//
//  MemoryDetailView.swift
//  Twofold
//

import SwiftUI

struct MemoryDetailView: View {
    let memory: Memory

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    MemoryPhotoView(memory: memory, cornerRadius: 12)
                        .frame(height: 320)
                        .padding(Theme.Spacing.sm)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .rotationEffect(.degrees(-2))
                }
                .padding(.top, Theme.Spacing.lg)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("\(memory.title) \(memory.emoji)")
                        .font(.title2.weight(.bold))
                    Text(memory.place.city)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                    Text(memory.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)

                    Divider().padding(.vertical, Theme.Spacing.xs)

                    Text(memory.note)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        MemoryDetailView(memory: MockData.memories[0])
    }
}
