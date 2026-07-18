//
//  RelationshipStatsPhotoPickerView.swift
//  Twofold
//
//  Lets the user override `RelationshipStatsShareView`'s default random selection with their
//  own specific picks for the "Our Story" snapshot's photo grid — capped at the same
//  `RelationshipStatsShareCard.maxStoryPhotos` the card itself enforces.
//

import SwiftUI

struct RelationshipStatsPhotoPickerView: View {
    let memories: [Memory]
    @Binding var selectedIDs: Set<Memory.ID>

    @Environment(\.dismiss) private var dismiss

    private var sortedMemories: [Memory] {
        memories.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text("Select up to \(RelationshipStatsShareCard.maxStoryPhotos) photos (\(selectedIDs.count)/\(RelationshipStatsShareCard.maxStoryPhotos))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .padding(.top, Theme.Spacing.sm)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    ForEach(sortedMemories) { memory in
                        thumbnail(memory)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Choose Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func thumbnail(_ memory: Memory) -> some View {
        let isSelected = selectedIDs.contains(memory.id)
        let isDisabled = !isSelected && selectedIDs.count >= RelationshipStatsShareCard.maxStoryPhotos
        return ZStack(alignment: .topTrailing) {
            MemoryPhotoView(memory: memory, cornerRadius: 12)
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isDisabled ? 0.4 : 1)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.skyBlue, lineWidth: 3)
                    }
                }

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, isSelected ? Theme.skyBlue : Color.black.opacity(0.35))
                .padding(6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedIDs.remove(memory.id)
            } else if selectedIDs.count < RelationshipStatsShareCard.maxStoryPhotos {
                selectedIDs.insert(memory.id)
            }
        }
    }
}

#Preview {
    RelationshipStatsPhotoPickerView(memories: MockData.memories, selectedIDs: .constant(Set(MockData.memories.prefix(2).map(\.id))))
}
