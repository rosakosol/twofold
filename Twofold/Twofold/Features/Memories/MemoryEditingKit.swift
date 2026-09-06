//
//  MemoryEditingKit.swift
//  Twofold
//
//  The two pieces of memory editing that both the full Add/Edit sheet and the detail screen's
//  in-place editing need, kept in one place so they cannot drift apart. A photo picked from the
//  detail screen has to be resized and encoded exactly the way one picked from the editor is, and
//  the date has to be picked the same way in both, or the same memory behaves differently
//  depending on which screen you happened to change it from.
//

import SwiftUI
import PhotosUI

// MARK: - Importing photos

/// Turns picked library items into upload-ready JPEG data.
///
/// Full-resolution originals are far larger than anything this app displays, so each one is
/// downscaled and re-encoded before it goes anywhere near the network — the same 1600pt / 0.8
/// quality the editor has always used.
enum MemoryPhotoImport {
    struct Loaded {
        let key: String
        let data: Data
        let image: UIImage
    }

    /// Every item's load, decode, downscale and encode runs concurrently. Done one after another,
    /// a full eight-photo selection means eight sequential decode/resize/encode passes over
    /// full-resolution source images before the last thumbnail appears.
    ///
    /// `loadTransferable` fails intermittently — most visibly in the Simulator, where
    /// PHPickerViewController's out-of-process handoff for seeded library assets often times out.
    /// Failures come back as a count rather than an error, so a caller can report "couldn't load 2
    /// of those" and let the person try again, instead of dropping them silently.
    static func load(_ items: [(item: PhotosPickerItem, key: String)]) async -> (loaded: [Loaded], failedCount: Int) {
        guard !items.isEmpty else { return ([], 0) }

        let results = await withTaskGroup(of: Loaded?.self) { group in
            for (item, key) in items {
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return nil }
                    let resized = uiImage.resized(maxDimension: 1600)
                    guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return nil }
                    return Loaded(key: key, data: jpeg, image: resized)
                }
            }
            var collected: [Loaded?] = []
            for await result in group { collected.append(result) }
            return collected
        }

        return (results.compactMap { $0 }, results.filter { $0 == nil }.count)
    }

    /// Stable per-item keys, so a selection that fires more than once (picking one more photo
    /// re-delivers the whole selection) doesn't import the same photo twice.
    static func keyed(_ items: [PhotosPickerItem]) -> [(item: PhotosPickerItem, key: String)] {
        items.map { ($0, $0.itemIdentifier ?? UUID().uuidString) }
    }

    static func failureMessage(count: Int) -> String? {
        switch count {
        case 0: nil
        case 1: "Couldn't load that photo — try selecting it again."
        default: "Couldn't load \(count) of those photos — try selecting them again."
        }
    }
}

// MARK: - Picking when

/// One picker for the day and the time together.
///
/// These used to be two separate sheets behind two separate toolbar buttons, which meant setting
/// when something happened took two trips: open the calendar, pick a day, dismiss, open the clock,
/// spin the wheel, dismiss. A graphical `DatePicker` asked for both components shows the calendar
/// with the time on a row beneath it, which is the same two choices in one visit.
struct MemoryDateTimeSheet: View {
    @Binding var date: Date
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "When",
                    selection: $date,
                    // A memory is something that already happened, so future dates stay
                    // unselectable — as they were when this was two pickers.
                    in: ...Date.now,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("When")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        // Tall enough for the calendar grid and the time row together. The scroll view above is
        // the safety net: on the smallest phones, or at the largest accessibility text sizes, the
        // grid outgrows even this and needs somewhere to go other than off the bottom edge.
        .presentationDetents([.height(560), .large])
    }
}

// MARK: - Managing a memory's photos

/// One photo on a memory, wherever it currently lives — already uploaded, or picked a moment ago
/// and not saved yet.
enum MemoryPhotoItem: Identifiable {
    case uploaded(MemoryPhoto)
    case pending(id: UUID, image: Image)

    var id: String {
        switch self {
        case .uploaded(let photo): "uploaded-\(photo.id)"
        case .pending(let id, _): "pending-\(id)"
        }
    }
}

/// The gallery, with the memory's own photos underneath it.
///
/// The system photo picker on its own cannot do this job. It can only show a photo as selected if
/// that photo is still an item in *this* device's library, so a photo that has been uploaded — or
/// one a partner added, which was never in this library at all — can never appear ticked there.
/// Handing someone the system picker to manage a memory's photos therefore leaves them permanently
/// unable to remove half of them: the ones they did not personally add are simply not in the
/// picker to untick.
///
/// So the two halves are separated. The picker above is only ever for adding, embedded inline
/// rather than presented, and the strip below is the memory as it actually stands — every photo on
/// it, whoever added it and wherever it came from, each removable. One list, one meaning, and
/// nothing that can only be reached by the person who happened to take the picture.
struct MemoryPhotosSheet: View {
    let photos: [MemoryPhotoItem]
    let isBusy: Bool
    var onAdd: ([Data]) async -> Void
    var onRemove: (MemoryPhotoItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [PhotosPickerItem] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PhotosPicker(selection: $picked, maxSelectionCount: 8, matching: .images) {
                    // Never drawn: an inline picker embeds the library itself and ignores its
                    // label. Required by the initialiser all the same.
                    EmptyView()
                }
                .photosPickerStyle(.inline)
                // The picker's own "Done"/"Cancel" bar would be a second, contradictory way out of
                // a sheet that already has one, and it is not what finishes this job — the strip
                // below is.
                .photosPickerAccessoryVisibility(.hidden, edges: .bottom)

                Divider()

                selectedStrip
                    .background(Theme.cardBackground)
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: picked) { _, items in
                Task { await add(items) }
            }
        }
    }

    private var selectedStrip: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(photos.isEmpty ? "No photos yet" : "On this memory")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(Theme.heartRed)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(photos) { photo in
                        thumbnail(photo)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)
            }
            // Holds its height with nothing in it, so removing the last photo doesn't collapse the
            // strip and jump the picker above it down the screen.
            .frame(height: 88)
        }
    }

    private func thumbnail(_ photo: MemoryPhotoItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch photo {
                case .uploaded(let uploaded):
                    MemoryPhotoThumbnail(photo: uploaded)
                case .pending(_, let image):
                    image.resizable().scaledToFill()
                }
            }
            .frame(width: 68, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                onRemove(photo)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
            }
            // The glyph stays pinned to the corner; only the tappable area grows inward to the
            // 44pt minimum, rather than the icon itself looking oversized.
            .frame(width: 44, height: 44, alignment: .topTrailing)
            .contentShape(Rectangle())
            .accessibilityLabel("Remove photo")
        }
        .frame(width: 68, height: 68, alignment: .topLeading)
    }

    private func add(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        errorMessage = nil
        let (loaded, failedCount) = await MemoryPhotoImport.load(MemoryPhotoImport.keyed(items))
        // Cleared before the await returns to the picker, so the library's ticks reset and the
        // strip below is the only place a chosen photo appears. Two places showing the same
        // selection would need reconciling every time either changed.
        picked = []
        if !loaded.isEmpty {
            await onAdd(loaded.map(\.data))
        }
        errorMessage = MemoryPhotoImport.failureMessage(count: failedCount)
    }
}

/// An already-uploaded photo, through the shared path-keyed cache rather than a plain `AsyncImage`,
/// so re-opening this sheet for the same memory resolves from cache instead of downloading again.
struct MemoryPhotoThumbnail: View {
    let photo: MemoryPhoto

    @State private var loadedImage: UIImage?

    private var cacheKey: String { photo.path == "pending" ? photo.url.absoluteString : photo.path }
    private var resolvedImage: UIImage? { loadedImage ?? MemoryPhotoImageCache.shared.image(for: cacheKey) }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage).resizable().scaledToFill()
            } else {
                Theme.cardBackground.task(id: cacheKey) { await load() }
            }
        }
    }

    private func load() async {
        if let cached = MemoryPhotoImageCache.shared.image(for: cacheKey) {
            loadedImage = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: photo.url), let image = UIImage(data: data) else { return }
        MemoryPhotoImageCache.shared.store(image, for: cacheKey)
        loadedImage = image
    }
}
