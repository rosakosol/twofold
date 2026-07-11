//
//  MemoriesListView.swift
//  Twofold
//

import SwiftUI

struct MemoriesListView: View {
    @Environment(AppModel.self) private var appModel

    private var sortedMemories: [Memory] {
        appModel.memories.sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if sortedMemories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.md) {
                        ForEach(sortedMemories) { memory in
                            NavigationLink {
                                MemoryDetailView(memory: memory)
                            } label: {
                                memoryRow(memory)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await appModel.deleteMemory(memory) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .padding(.bottom, 64)
                }
            }
        }
    }

    private func memoryRow(_ memory: Memory) -> some View {
        SectionCard {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                MemoryPhotoView(memory: memory, cornerRadius: 14)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(memory.title) \(memory.emoji)")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(memory.place.city)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
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
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            SectionCard {
                HStack(spacing: Theme.Spacing.md) {
                    ZStack {
                        Circle().fill(Theme.skyBlue.opacity(0.15))
                        Image(systemName: "photo.badge.plus").foregroundStyle(Theme.skyBlue)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your first memory").font(.headline)
                        Text("Tap + above to save a photo from a moment together.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Theme.Spacing.md)
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        MemoriesListView()
            .environment(AppModel())
            .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
