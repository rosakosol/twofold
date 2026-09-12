//
//  DrawingPadFullScreenView.swift
//  Twofold
//
//  Read-only full-screen viewer for a partner's drawing pad — DrawingPadEditorView is
//  edit-and-save only and always targets "your" pad, so it isn't reusable here as-is.
//

import PostHog
import SwiftUI

struct DrawingPadFullScreenView: View {
    let title: String
    let url: URL?
    /// The navigation title, when the possessive form built below isn't the right one. Defaults to
    /// nil, which keeps "<name>'s pad" — correct for the partner's pad, which is what this screen
    /// was built for and still its usual caller. `DrawingPadPairView` also opens *your* pad from
    /// here, where that same composition would read "You's pad".
    var screenTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            // Matches `DrawingPadEditorView`'s canvas treatment (white card,
                            // rounded corners, soft shadow) — the read-only viewer had been
                            // showing the same image full-bleed with no card framing at all.
                            image
                                .resizable()
                                .scaledToFit()
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
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
            .navigationTitle(screenTitle ?? "\(title)'s pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .postHogScreenView("Drawing Pad: Partner View")
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
    DrawingPadFullScreenView(title: "Ewin", url: nil)
        .environment(AppModel())
}
