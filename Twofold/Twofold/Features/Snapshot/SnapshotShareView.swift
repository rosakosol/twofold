//
//  SnapshotShareView.swift
//  Twofold
//

import SwiftUI

struct SnapshotShareView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var selectedTheme: SnapshotTheme = .classic
    @State private var renderedImage: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ScrollView {
                    SnapshotThemeCard(couple: appModel.couple, stats: appModel.stats, theme: selectedTheme)
                        .padding(.top, Theme.Spacing.lg)
                        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
                }

                themePicker
                    .padding(.bottom, Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: renderCardImage(),
                        preview: SharePreview("Our story so far", image: renderCardImage())
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var themePicker: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(SnapshotTheme.allCases) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: theme.icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(selectedTheme == theme ? Theme.skyBlue : Theme.cardBackground, in: Circle())
                            .foregroundStyle(selectedTheme == theme ? .white : Theme.ink)
                        Text(theme.rawValue).font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func renderCardImage() -> Image {
        let renderer = ImageRenderer(
            content: SnapshotThemeCard(couple: appModel.couple, stats: appModel.stats, theme: selectedTheme)
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            return Image(uiImage: uiImage)
        }
        return Image(systemName: "photo")
    }
}

#Preview {
    SnapshotShareView()
        .environment(AppModel())
}
