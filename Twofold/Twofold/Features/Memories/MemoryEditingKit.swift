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
