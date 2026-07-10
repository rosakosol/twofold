//
//  RoundPhotoPicker.swift
//  Twofold
//
//  Shared circular photo-picker widget used anywhere onboarding collects a profile photo
//  (your own, or a placeholder photo of your partner). Only picks/resizes/hands back JPEG
//  data via `onPick` — callers decide whether to hold it locally or upload immediately,
//  since that differs by screen (pre- vs. post-account-creation).
//

import SwiftUI
import PhotosUI
import UIKit

struct RoundPhotoPicker: View {
    var placeholderSystemImage: String = "camera.fill"
    var initialImageData: Data?
    /// Falls back to the existing remote photo (e.g. `Person.avatarURL`) when there's no local
    /// `initialImageData` to seed from — without this, a screen like Settings that only ever
    /// knows the avatar as a URL would show the empty "add a photo" state even when a photo is
    /// already set, which reads as "my photo didn't save" even though it did.
    var initialImageURL: URL?
    var size: CGFloat = 100
    var onPick: (Data) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var isLoading = false

    private var hasImage: Bool { previewImage != nil || initialImageURL != nil }

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                } else if let initialImageURL {
                    AsyncImage(url: initialImageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            placeholderContent
                        }
                    }
                } else {
                    placeholderContent
                }
                if isLoading {
                    Circle().fill(.black.opacity(0.3))
                    ProgressView().tint(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                if !hasImage {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Theme.skyBlue, Theme.leafGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                    )
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !hasImage {
                    ZStack {
                        Circle().fill(Theme.skyBlue)
                        Image(systemName: "plus")
                            .font(.system(size: size * 0.14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            guard previewImage == nil, let initialImageData, let uiImage = UIImage(data: initialImageData) else { return }
            previewImage = Image(uiImage: uiImage)
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await load(newItem) }
        }
    }

    // Soft brand-gradient fill with a dashed ring and a "+" badge (drawn separately above), so
    // the empty state reads as an inviting "add a photo" spot rather than a plain gray circle.
    private var placeholderContent: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Theme.skyBlue.opacity(0.22), Theme.leafGreen.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            Image(systemName: placeholderSystemImage)
                .font(.system(size: size * 0.34))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.skyBlue, Theme.leafGreen],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoading = true
        defer { isLoading = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else { return }
        let resized = uiImage.resized(maxDimension: 512)
        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else { return }
        previewImage = Image(uiImage: resized)
        onPick(jpegData)
    }
}
