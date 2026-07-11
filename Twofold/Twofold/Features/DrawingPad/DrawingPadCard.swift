//
//  DrawingPadCard.swift
//  Twofold
//

import SwiftUI

struct DrawingPadCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingEditor = false

    var body: some View {
        SectionCard {
            Text("Doodle pad")
                .font(.headline)
            HStack(spacing: Theme.Spacing.md) {
                padPreview(title: "You", url: appModel.myDrawingURL, isMine: true)
                padPreview(title: appModel.partner.name, url: appModel.partnerDrawingURL, isMine: false)
            }
        }
        .sheet(isPresented: $showingEditor) {
            DrawingPadEditorView()
        }
        .onAppear { appModel.loadDrawingPads() }
    }

    private func padPreview(title: String, url: URL?, isMine: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                guard isMine else { return }
                showingEditor = true
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                    if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else if isMine {
                                emptyPadHint
                            }
                        }
                    } else if isMine {
                        emptyPadHint
                    }
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.subtleInk.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isMine)

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyPadHint: some View {
        VStack(spacing: 4) {
            Image(systemName: "pencil.and.scribble")
            Text("Tap to draw").font(.caption2)
        }
        .foregroundStyle(Theme.subtleInk)
    }
}

#Preview {
    DrawingPadCard()
        .environment(AppModel())
        .padding()
        .background(Theme.backgroundGradient)
}
