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
    @State private var mode: MemoriesViewMode = .list
    @State private var showingAddMemory = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    switch mode {
                    case .list: MemoriesListView()
                    case .map: MemoriesMapView()
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
        .background(.white, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private func toggleButton(mode target: MemoriesViewMode, systemImage: String) -> some View {
        Button {
            withAnimation(.snappy) { mode = target }
        } label: {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 44, height: 36)
                .foregroundStyle(mode == target ? .white : Theme.subtleInk)
                .background(mode == target ? AnyShapeStyle(Theme.skyBlue) : AnyShapeStyle(.clear), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MemoriesView()
        .environment(AppModel())
}
