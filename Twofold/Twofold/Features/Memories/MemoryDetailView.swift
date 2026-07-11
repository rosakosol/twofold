//
//  MemoryDetailView.swift
//  Twofold
//

import SwiftUI

struct MemoryDetailView: View {
    private let memoryID: Memory.ID

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    init(memory: Memory) {
        memoryID = memory.id
    }

    private var memory: Memory? {
        appModel.memories.first { $0.id == memoryID }
    }

    var body: some View {
        Group {
            if let memory {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        photoCarousel(for: memory)
                            .padding(.top, Theme.Spacing.lg)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(memory.title)
                                .font(.title2.weight(.bold))
                            if let place = memory.place {
                                Text(place.city)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.subtleInk)
                            }
                            Text(memory.date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)

                            if !memory.note.isEmpty {
                                Divider().padding(.vertical, Theme.Spacing.xs)
                                Text(memory.note)
                                    .font(.body)
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingEdit = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                confirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .confirmationDialog("Delete this memory?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await appModel.deleteMemory(memory)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(isPresented: $showingEdit) {
                    AddMemoryView(existingMemory: memory)
                }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func photoCarousel(for memory: Memory) -> some View {
        Group {
            if memory.photos.count > 1 {
                TabView {
                    ForEach(memory.photos) { photo in
                        AsyncImage(url: photo.url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Theme.cardBackground
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 320)
            } else {
                MemoryPhotoView(memory: memory, cornerRadius: 12)
                    .frame(height: 320)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .rotationEffect(.degrees(-2))
    }
}

#Preview {
    NavigationStack {
        MemoryDetailView(memory: MockData.memories[0])
            .environment(AppModel())
    }
}
