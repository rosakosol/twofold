//
//  DoodlePadFullScreenView.swift
//  Twofold
//
//  Read-only full-screen viewer for a partner's doodle pad — DrawingPadEditorView is
//  edit-and-save only and always targets "your" pad, so it isn't reusable here as-is.
//

import SwiftUI

struct DoodlePadFullScreenView: View {
    let title: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(Theme.Spacing.lg)
                        } else if phase.error != nil {
                            emptyState
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    emptyState
                }
            }
            .navigationTitle("\(title)'s pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "pencil.and.scribble")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text("Nothing drawn yet")
                .foregroundStyle(Theme.subtleInk)
        }
    }
}

#Preview {
    DoodlePadFullScreenView(title: "Ewin", url: nil)
        .environment(AppModel())
}
