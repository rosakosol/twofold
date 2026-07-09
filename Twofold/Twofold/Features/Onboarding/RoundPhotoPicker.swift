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
    var size: CGFloat = 100
    var onPick: (Data) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var isLoading = false

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                if let previewImage {
                    previewImage
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle().fill(Theme.cardBackground)
                    Image(systemName: placeholderSystemImage)
                        .font(.title2)
                        .foregroundStyle(Theme.subtleInk)
                }
                if isLoading {
                    Circle().fill(.black.opacity(0.3))
                    ProgressView().tint(.white)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
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
