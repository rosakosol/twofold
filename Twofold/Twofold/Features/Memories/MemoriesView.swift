//
//  MemoriesView.swift
//  Twofold
//
//  Tab root for Memories — hosts the list/map content and a floating pill that toggles
//  between the two, plus the "+" entry point for adding a new memory.
//

import SwiftUI

private enum MemoriesViewMode {
    case list, map
}

struct MemoriesView: View {
    @Environment(AppModel.self) private var appModel
    @State private var mode: MemoriesViewMode = .map
    @State private var showingAddMemory = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch mode {
                    case .list: MemoriesListView(onTapAddMemory: { showingAddMemory = true })
                    case .map: MemoriesMapView(onTapAddMemory: { showingAddMemory = true })
                    }
                }

                modeToggle
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Memories")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    // A bare glyph button leaves VoiceOver to guess from the symbol name; the
                    // other tab roots (see `GamesHubView`'s toolbar) all name theirs explicitly.
                    .accessibilityLabel("Add memory")
                }
            }
            .sheet(isPresented: $showingAddMemory) {
                AddMemoryView()
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            toggleButton(mode: .list, systemImage: "list.bullet")
            toggleButton(mode: .map, systemImage: "map")
        }
        .padding(4)
        .background(Theme.cardBackground, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private func toggleButton(mode target: MemoriesViewMode, systemImage: String) -> some View {
        Button {
            withAnimation(.snappy) { mode = target }
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 44, height: 44)
                .foregroundStyle(mode == target ? .white : Theme.subtleInk)
                .background(mode == target ? AnyShapeStyle(Theme.skyBlue) : AnyShapeStyle(.clear), in: Capsule())
                // The 44x44 frame above sets the *layout* size, but without a content shape the
                // hittable and accessibility region stayed the glyph's own bounds — measured at
                // 16.7x12.3pt by the accessibility audit, roughly a seventh of the area this
                // looks like it offers.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .list ? "List view" : "Map view")
        .accessibilityAddTraits(mode == target ? .isSelected : [])
    }
}

#Preview {
    MemoriesView()
        .environment(AppModel())
}
