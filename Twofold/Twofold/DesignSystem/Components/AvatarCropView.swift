//
//  AvatarCropView.swift
//  Twofold
//
//  Drag-to-reposition, pinch-to-zoom crop step shown after picking a photo for an avatar —
//  `RoundPhotoPicker` previously always auto-centered the raw picked image with no way to choose66
//  what actually ends up inside the circle. Renders a square crop at output resolution matching
//  exactly what the circular preview shows, so what you see is what gets uploaded.
//

import SwiftUI

struct AvatarCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onComplete: (UIImage) -> Void

    private let cropDiameter: CGFloat = 280
    private let outputDimension: CGFloat = 600
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Spacer(minLength: 0)

                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cropDiameter, height: cropDiameter)
                        .scaleEffect(scale)
                        .offset(offset)
                }
                .frame(width: cropDiameter, height: cropDiameter)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .contentShape(Circle())
                .gesture(
                    SimultaneousGesture(dragGesture, magnificationGesture)
                )

                Text("Drag to reposition · pinch to zoom")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Adjust photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") { onComplete(renderCrop()) }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(maxScale, max(minScale, lastScale * value))
            }
            .onEnded { _ in lastScale = scale }
    }

    /// Re-renders the same fill/scale/offset math at `outputDimension` instead of the on-screen
    /// `cropDiameter` — the offset (captured in on-screen points) has to scale up by the same
    /// ratio, or panning near the preview's edges would crop a different region than what was
    /// actually shown.
    private func renderCrop() -> UIImage {
        let ratio = outputDimension / cropDiameter
        let scaledOffset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
        let content = Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: outputDimension, height: outputDimension)
            .scaleEffect(scale)
            .offset(scaledOffset)
            .frame(width: outputDimension, height: outputDimension)
            .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.uiImage ?? image
    }
}
