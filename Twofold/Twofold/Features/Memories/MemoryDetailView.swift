//
//  MemoryDetailView.swift
//  Twofold
//
//  A memory, editable where it is shown.
//
//  Changing anything used to mean opening the full Add/Edit sheet, which is a whole second screen
//  with its own map, its own toolbar and its own Save button — a lot of ceremony for fixing a typo
//  in a title or adding one more photo. Everything on this screen is now a tap target that edits
//  the thing you tapped: the title becomes a text field in place, the location and the date open
//  their pickers directly, and the corner of the photo adds or removes photos.
//
//  Each edit writes on its own rather than accumulating behind a Save button. There is nothing to
//  submit and nothing to lose by leaving, which is the point of editing in place; the full sheet
//  is still there under "Edit" for writing the note, which wants a bigger field than this screen
//  has room for.
//

import PhotosUI
import PostHog
import SwiftUI

struct MemoryDetailView: View {
    private let memoryID: Memory.ID

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false

    @State private var draftTitle = ""
    @FocusState private var titleFocused: Bool
    @State private var showingLocationSearch = false
    @State private var showingDatePicker = false
    /// Held locally while the picker is open, and written once on Done — binding the picker
    /// straight through to the store would save on every spin of the wheel.
    @State private var draftDate = Date.now

    @State private var showingPhotoPicker = false
    @State private var isAddingPhotos = false
    /// Which page of the carousel is showing, so "Remove this photo" removes the one being looked
    /// at rather than always the first.
    @State private var visiblePhotoIndex = 0
    @State private var errorMessage: String?

    init(memory: Memory) {
        memoryID = memory.id
    }

    private var memory: Memory? {
        appModel.memories.first { $0.id == memoryID }
    }

    var body: some View {
        Group {
            if let memory {
                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        photoCarousel(for: memory)
                            .padding(.top, Theme.Spacing.lg)

                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            titleField(for: memory)
                            locationRow(for: memory)
                            dateRow(for: memory)

                            if !memory.note.isEmpty {
                                Divider().padding(.vertical, Theme.Spacing.xs)
                                Text(memory.note)
                                    .font(.body)
                                    .foregroundStyle(Theme.ink)
                            }

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(Theme.heartRed)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.lg)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button {
                                showingEdit = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                confirmingDelete = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More options")
                    }
                }
                .confirmationDialog("Delete this memory?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        Task {
                            await appModel.deleteMemory(memory)
                            dismiss()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .sheet(isPresented: $showingPhotoPicker) {
                    MemoryPhotosSheet(
                        photos: memory.photos.map { .uploaded($0) },
                        isBusy: isAddingPhotos,
                        onAdd: { data in await addPhotos(data) },
                        onRemove: { item in
                            if case .uploaded(let photo) = item {
                                // Step the carousel back first, or removing the page being looked
                                // at leaves it on an index that no longer exists.
                                visiblePhotoIndex = max(0, min(visiblePhotoIndex, memory.photos.count - 2))
                                Task { await appModel.removePhoto(photo, from: memory) }
                            }
                        }
                    )
                }
                .sheet(isPresented: $showingEdit) {
                    AddMemoryView(existingMemory: memory)
                }
                .sheet(isPresented: $showingLocationSearch) {
                    MemoryLocationSearchView { selected in
                        apply { $0.place = selected }
                    }
                }
                .sheet(isPresented: $showingDatePicker) {
                    MemoryDateTimeSheet(date: $draftDate) {
                        showingDatePicker = false
                        apply { $0.date = draftDate }
                    }
                }
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Memories: Memory Detail")
    }

    // MARK: - Editing in place

    /// Reads the memory back out of the store before mutating, rather than editing a copy captured
    /// when the view was built — an edit made a moment after another one (or after a partner's
    /// change arrived) would otherwise write the stale copy back and undo it.
    private func apply(_ mutate: (inout Memory) -> Void) {
        guard var updated = memory else { return }
        mutate(&updated)
        Task { await appModel.updateMemory(updated) }
    }

    /// The title is always a `TextField`; tapping it just starts editing. A `Text` that swaps for a
    /// field on tap has to be tapped twice — once to become a field, once to put the caret where
    /// you meant — and the first tap looks like it did nothing.
    private func titleField(for memory: Memory) -> some View {
        TextField("Title", text: $draftTitle)
            .font(.title2.weight(.bold))
            .focused($titleFocused)
            .submitLabel(.done)
            .onAppear { draftTitle = memory.title }
            // Follows the stored title while someone else is not mid-edit, so a change made in the
            // full editor (or by a partner) shows here rather than being held off by the draft.
            .onChange(of: memory.title) { _, newTitle in
                guard !titleFocused else { return }
                draftTitle = newTitle
            }
            .onSubmit { commitTitle(for: memory) }
            .onChange(of: titleFocused) { _, focused in
                if !focused { commitTitle(for: memory) }
            }
    }

    /// Empty titles are refused rather than saved — a memory with no title is unfindable in a list.
    /// The field snaps back to what it was.
    private func commitTitle(for memory: Memory) {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            draftTitle = memory.title
            return
        }
        guard trimmed != memory.title else { return }
        apply { $0.title = trimmed }
    }

    private func locationRow(for memory: Memory) -> some View {
        Button {
            showingLocationSearch = true
        } label: {
            editableRow(
                text: memory.place?.city ?? "Add a location",
                font: .subheadline,
                icon: "mappin.and.ellipse",
                muted: memory.place == nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(memory.place.map { "Location, \($0.city). Tap to change" } ?? "Add a location")
    }

    private func dateRow(for memory: Memory) -> some View {
        Button {
            draftDate = memory.date
            showingDatePicker = true
        } label: {
            editableRow(
                text: memory.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute()),
                font: .caption,
                icon: "calendar",
                muted: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tap to change the date and time")
    }

    /// A small leading glyph is what marks these as tappable. Without it they read as the plain
    /// captions they used to be, and nobody thinks to touch them.
    private func editableRow(text: String, font: Font, icon: String, muted: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(font)
                .foregroundStyle(muted ? Theme.heartRed : Theme.subtleInk)
            Text(text)
                .font(muted ? font.weight(.medium) : font)
                .foregroundStyle(muted ? Theme.heartRed : Theme.subtleInk)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Photos

    private func addPhotos(_ imagesData: [Data]) async {
        guard !imagesData.isEmpty, let current = memory else { return }
        isAddingPhotos = true
        errorMessage = nil
        await appModel.updateMemory(current, newImagesData: imagesData)
        isAddingPhotos = false
    }

    @ViewBuilder
    private func photoCarousel(for memory: Memory) -> some View {
        Group {
            if memory.photos.count > 1 {
                TabView(selection: $visiblePhotoIndex) {
                    ForEach(Array(memory.photos.enumerated()), id: \.element.id) { index, photo in
                        AsyncImage(url: photo.url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Theme.cardBackground
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 320)
            } else {
                MemoryPhotoView(memory: memory, cornerRadius: 12)
                    .frame(height: 320)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .rotationEffect(.degrees(-2))
        // While an upload is going. This used to live inside the edit button, which no longer
        // exists, and the picker dismisses before the photo appears — so with nothing here at all,
        // a slow upload looks like a tap that did nothing.
        .overlay {
            if isAddingPhotos {
                ProgressView()
                    .tint(.white)
                    .padding(Theme.Spacing.md)
                    .background(.black.opacity(0.45), in: Circle())
            }
        }
        // The photo *is* the button. `contentShape` because the card is mostly the image's own
        // clipped shape and its white border, and a tap on the border should count too.
        //
        // `simultaneousGesture` rather than `onTapGesture`, so the tap never has to win an argument
        // with the paging TabView's scroll view underneath it. A page view responds to drags rather
        // than taps and should not contest this, but an exclusive gesture only has to lose once to
        // make the photo look unresponsive, and a simultaneous one cannot lose. Swiping between
        // photos is unaffected either way.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { showingPhotoPicker = true })
        // Room for the corners. Tilting the card pushes them past the edges of the space it was
        // laid out in, so at full screen width they were cut off against the sides.
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        .accessibilityElement()
        .accessibilityLabel(memory.photos.isEmpty ? "Add photos" : "Photos. \(memory.photos.count) of them")
        .accessibilityHint("Tap to add or remove photos")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        MemoryDetailView(memory: MockData.memories[0])
            .environment(AppModel())
    }
}
