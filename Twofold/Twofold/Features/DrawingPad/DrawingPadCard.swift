//
//  DrawingPadCard.swift
//  Twofold
//

import SwiftUI

struct DrawingPadCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingEditor = false
    @State private var showingPartnerFullScreen = false

    var body: some View {
        SectionCard {
            Text("Drawing pad")
                .font(.headline)
            HStack(spacing: Theme.Spacing.md) {
                padPreview(title: "You", url: appModel.myDrawingURL, isMine: true)
                padPreview(title: appModel.partner.name, url: appModel.partnerDrawingURL, isMine: false)
            }
        }
        .sheet(isPresented: $showingEditor) {
            DrawingPadEditorView()
        }
        .fullScreenCover(isPresented: $showingPartnerFullScreen) {
            DrawingPadFullScreenView(title: appModel.partner.name, url: appModel.partnerDrawingURL)
        }
        .onAppear { appModel.loadDrawingPads() }
    }

    private func padPreview(title: String, url: URL?, isMine: Bool) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                if isMine {
                    showingEditor = true
                } else {
                    showingPartnerFullScreen = true
                }
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
            // No `.disabled(!isMine)` here anymore — that was the actual cause of the partner's
            // pad looking "transparent/muted": SwiftUI dims a disabled Button's label by default,
            // which reads exactly like a rendering/opacity bug even though nothing about the
            // image itself was ever altered. Both previews are tappable now, just to different
            // destinations (edit vs. view full screen).
            .buttonStyle(.plain)

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
