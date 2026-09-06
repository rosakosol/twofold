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

    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
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
                .confirmationDialog("Photos", isPresented: $showingPhotoOptions, titleVisibility: .hidden) {
                    Button("Add photos") { showingPhotoPicker = true }
                    if !memory.photos.isEmpty {
                        Button("Remove this photo", role: .destructive) { removeVisiblePhoto(from: memory) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection, maxSelectionCount: 8, matching: .images)
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
                .onChange(of: photoSelection) { _, newItems in
                    Task { await addPhotos(newItems, to: memory) }
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

    private func addPhotos(_ items: [PhotosPickerItem], to memory: Memory) async {
        guard !items.isEmpty else { return }
        isAddingPhotos = true
        errorMessage = nil
        let (loaded, failedCount) = await MemoryPhotoImport.load(MemoryPhotoImport.keyed(items))
        if !loaded.isEmpty, let current = self.memory {
            await appModel.updateMemory(current, newImagesData: loaded.map(\.data))
        }
        errorMessage = MemoryPhotoImport.failureMessage(count: failedCount)
        // Cleared so picking the same photo again still registers as a change.
        photoSelection = []
        isAddingPhotos = false
    }

    private func removeVisiblePhoto(from memory: Memory) {
        guard memory.photos.indices.contains(visiblePhotoIndex) else { return }
        let photo = memory.photos[visiblePhotoIndex]
        // Step back first, or removing the last page leaves the carousel on an index that no
        // longer exists and it renders blank.
        visiblePhotoIndex = max(0, visiblePhotoIndex - 1)
        Task { await appModel.removePhoto(photo, from: memory) }
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
        // Sits on the corner of the photo card and turns with it, so it stays on the corner rather
        // than floating beside a tilted card. Outside the rotation it would drift away from the
        // edge it is supposed to belong to.
        .overlay(alignment: .bottomTrailing) { photoEditButton }
        .accessibilityElement(children: .contain)
    }

    private var photoEditButton: some View {
        Button {
            showingPhotoOptions = true
        } label: {
            Group {
                if isAddingPhotos {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
            .background(Theme.heartRed, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isAddingPhotos)
        // Half off the card's corner, the way the count badge sits on a map pin — on the photo
        // without covering the part of it worth looking at.
        .offset(x: 6, y: 6)
        .accessibilityLabel("Add or remove photos")
    }
}

#Preview {
    NavigationStack {
        MemoryDetailView(memory: MockData.memories[0])
            .environment(AppModel())
    }
}
