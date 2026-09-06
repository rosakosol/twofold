//
//  AddMemoryView.swift
//  Twofold
//

import SwiftUI
import PhotosUI
import PostHog
import MapKit

struct AddMemoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private let existingMemory: Memory?
    /// `false` for onboarding's mandatory first-memory step (see `FirstMemoryView`) — hides the
    /// Cancel button and disables swipe-to-dismiss, so saving a memory is the only way off this
    /// screen. Every other call site (the real Memories tab) leaves this at the default.
    var isDismissable: Bool = true
    /// Set when opened from a specific location's context (a map pin's memory list) so the new
    /// memory doesn't default to the device's current location/home city instead.
    private let initialPlace: Place?
    /// Set when opened from a trip's "Link a memory" screen's "Create new" option — the new
    /// memory gets linked to this trip immediately after it's created, the same way picking an
    /// already-existing memory there calls `AppModel.linkMemory`.
    private let linkToTrip: Trip?
    /// Fires once saving succeeds, after `dismiss()` is queued — lets a caller that presented
    /// this as a nested sheet (e.g. `LinkMemoryPickerView`) also close itself, rather than
    /// leaving the caller's own screen up once its actual goal (getting a memory linked) is done.
    private let onSaved: (() -> Void)?

    @State private var title: String
    @State private var place: Place?
    @State private var date: Date
    @State private var note: String
    @State private var existingPhotos: [MemoryPhoto]

    @State private var pendingPhotos: [PendingPhoto] = []
    @State private var showingPhotosSheet = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var showingDatePicker = false
    @State private var showingLocationSearch = false
    @State private var locationService = HomeLocationService()
    @State private var mapCameraPosition: MapCameraPosition
    /// Enough map to place the pin and read the streets around it, without taking room the form
    /// needs. A point value rather than a fraction of the screen: this is a header, and a header
    /// that's a third of a small phone and a quarter of a large one is the same header drawn
    /// inconsistently.
    private static let mapHeight: CGFloat = 150

    private enum Field: Hashable { case title, note }
    /// Drives the map's shrink-while-editing-notes behavior below — the map used to stay fixed at
    /// half the screen even with the keyboard up, leaving barely any room to actually see what
    /// you were typing in the notes field. Cleared to `nil` automatically once the keyboard is
    /// dismissed (tap-outside, app-wide — see `KeyboardDismissal`), since `@FocusState` tracks the
    /// real first-responder state rather than needing its own explicit reset.
    @FocusState private var focusedField: Field?

    private struct PendingPhoto: Identifiable {
        let id = UUID()
        var image: Image
        var data: Data
    }

    init(
        existingMemory: Memory? = nil,
        isDismissable: Bool = true,
        initialPlace: Place? = nil,
        linkToTrip: Trip? = nil,
        onSaved: (() -> Void)? = nil
    ) {
        self.existingMemory = existingMemory
        self.isDismissable = isDismissable
        self.initialPlace = initialPlace
        self.linkToTrip = linkToTrip
        self.onSaved = onSaved
        _title = State(initialValue: existingMemory?.title ?? "")
        let startingPlace = existingMemory?.place ?? initialPlace
        _place = State(initialValue: startingPlace)
        _date = State(initialValue: existingMemory?.date ?? .now)
        _note = State(initialValue: existingMemory?.note ?? "")
        _existingPhotos = State(initialValue: existingMemory?.photos ?? [])
        _mapCameraPosition = State(initialValue: startingPlace.map {
            .region(MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
        } ?? .automatic)
    }

    private var isEditing: Bool { existingMemory != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Both heights are fixed. The map used to be half the screen and give that height
                // up as the form scrolled, which meant two things moving at once for the whole
                // length of the page; the shrunken end of that was where it read best, so it just
                // starts there and stays. No GeometryReader, no scroll observation, nothing to
                // desynchronise.
                locationMap
                    .frame(height: Self.mapHeight)

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        titleRow
                        dateLocationSummary
                        noteField

                        if !existingPhotos.isEmpty || !pendingPhotos.isEmpty {
                            photoStrip
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRed)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .padding(.bottom, 72)
                }
                bottomBar
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit memory" : "Add a memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .interactiveDismissDisabled(!isDismissable)
            .onAppear {
                // New memories default to the device's actual current location (falling back to
                // the user's own home city until/unless that resolves) — location is required to
                // save, so this means most people never have to think about it, while still
                // leaving it changeable for a memory made somewhere else.
                if !isEditing, place == nil {
                    place = appModel.currentUser.homeCity
                    locationService.requestCurrentLocation()
                }
            }
            .onChange(of: locationService.state) { _, newState in
                guard case .resolved(let resolved) = newState else { return }
                // Only replace the home-city fallback set above — never a location the user has
                // since picked manually (from the search sheet) while this was still resolving.
                guard place == appModel.currentUser.homeCity else { return }
                place = resolved
            }
            .onChange(of: place) { _, newPlace in
                guard let newPlace else { return }
                withAnimation {
                    mapCameraPosition = .region(MKCoordinateRegion(center: newPlace.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
                }
            }
            .sheet(isPresented: $showingPhotosSheet) {
                MemoryPhotosSheet(
                    photos: existingPhotos.map { .uploaded($0) } + pendingPhotos.map { .pending(id: $0.id, image: $0.image) },
                    isBusy: false,
                    onAdd: { data in
                        for imageData in data {
                            guard let image = UIImage(data: imageData) else { continue }
                            pendingPhotos.append(PendingPhoto(image: Image(uiImage: image), data: imageData))
                        }
                    },
                    onRemove: { item in
                        switch item {
                        case .uploaded(let photo): removeExistingPhoto(photo)
                        case .pending(let id, _): pendingPhotos.removeAll { $0.id == id }
                        }
                    }
                )
            }
            .sheet(isPresented: $showingLocationSearch) {
                MemoryLocationSearchView { selected in place = selected }
            }
            .sheet(isPresented: $showingDatePicker) {
                MemoryDateTimeSheet(date: $date) { showingDatePicker = false }
            }
        }
        .postHogScreenView("Memories: Add/Edit Memory")
    }

    /// Fills the top half of the screen (see `body`) — a live preview of the memory's location,
    /// centered on the device's current location by default (same value `place` itself defaults
    /// to) and recentering whenever `place` changes. Tapping it opens the same location search
    /// sheet the mappin toolbar icon does, so it doubles as a large, obvious tap target for
    /// changing the location rather than just a static preview.

    private var locationMap: some View {
        Map(position: $mapCameraPosition) {
            if let place {
                Marker(place.displayCity, coordinate: place.coordinate)
                    .tint(Theme.heartRed)
            }
        }
        .onTapGesture { showingLocationSearch = true }
    }

    private var titleRow: some View {
        TextField("Memory title", text: $title)
            .font(.title2.weight(.bold))
            .focused($focusedField, equals: .title)
    }

    private var dateLocationSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                showingDatePicker = true
            } label: {
                Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
            .buttonStyle(.plain)
            if let place {
                Button {
                    showingLocationSearch = true
                } label: {
                    Text(place.city)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    showingLocationSearch = true
                } label: {
                    Text("Location required — tap to set")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.heartRed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noteField: some View {
        TextField("Write a few words about this memory", text: $note, axis: .vertical)
            .lineLimit(6...12)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .themedCardBackground(cornerRadius: Theme.Radius.card)
            .focused($focusedField, equals: .note)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(existingPhotos) { photo in
                    ZStack(alignment: .topTrailing) {
                        MemoryPhotoThumbnail(photo: photo)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        removeButton { removeExistingPhoto(photo) }
                    }
                }
                ForEach(pendingPhotos) { pending in
                    photoThumbnail(image: pending.image) {
                        pendingPhotos.removeAll { $0.id == pending.id }
                    }
                }
            }
        }
    }

    private func photoThumbnail(image: Image, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            image.resizable().scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            removeButton(action: remove)
        }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
                .font(.title3)
        }
        // The icon itself stays visually pinned to the corner (both this frame and the
        // `photoThumbnail` ZStack it sits in align `.topTrailing`) — only the tappable area
        // grows to Apple's 44x44pt minimum, extending inward over the thumbnail rather than
        // making the icon itself look oversized.
        .frame(width: 44, height: 44, alignment: .topTrailing)
        .contentShape(Rectangle())
        .accessibilityLabel("Remove photo")
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Opens `MemoryPhotosSheet` rather than the system picker directly. The system picker
            // can only tick a photo that is still in this device's library, so it can never offer
            // to remove one a partner added — see that type's own comment.
            Button { showingPhotosSheet = true } label: { iconCircle("photo.badge.plus") }
                .accessibilityLabel("Photos")
            // One button, not a calendar and a clock. Both opened a picker for half the same
            // value; `MemoryDateTimeSheet` sets the whole thing in one visit.
            Button { showingDatePicker = true } label: { iconCircle("calendar") }
                .accessibilityLabel("Date and time")
            Button { showingLocationSearch = true } label: {
                iconCircle(place == nil ? "mappin" : "mappin.circle.fill")
                    .overlay(alignment: .topTrailing) {
                        if place == nil {
                            Circle()
                                .fill(Theme.heartRed)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(Theme.cardBackground, lineWidth: 1.5))
                        }
                    }
            }

            Spacer()

            // Onboarding's mandatory first-memory step only — every other call site already has
            // a Cancel button in the toolbar (see `isDismissable` above), so a second way out
            // here would be redundant. Plain `dismiss()`, no save — `FirstMemoryView`'s own
            // `onDismiss` fires on any dismissal regardless of cause, so onboarding advances
            // exactly the same way it would after a real save, just without a memory to show for it.
            if !isDismissable {
                Button("Skip") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.subtleInk)
            }

            Button(action: save) {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .background(
                canSave ? AnyShapeStyle(Theme.primaryButtonGradient) : AnyShapeStyle(Theme.subtleInk.opacity(0.3)),
                in: Capsule()
            )
            .disabled(!canSave)
        }
        .padding(Theme.Spacing.md)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Theme.backgroundBottom.opacity(0), location: 0),
                    .init(color: Theme.backgroundBottom, location: 0.4),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func iconCircle(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(Theme.ink)
            .frame(width: 40, height: 40)
            .background(Theme.cardBackground, in: Circle())
    }

    private func removeExistingPhoto(_ photo: MemoryPhoto) {
        existingPhotos.removeAll { $0.id == photo.id }
        guard let existingMemory else { return }
        Task { await appModel.removePhoto(photo, from: existingMemory) }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let imagesData = pendingPhotos.map(\.data)

        Task {
            if var existingMemory {
                existingMemory.title = trimmedTitle
                existingMemory.place = place
                existingMemory.date = date
                existingMemory.note = trimmedNote
                await appModel.updateMemory(existingMemory, newImagesData: imagesData)
            } else {
                let memory = await appModel.addMemory(title: trimmedTitle, place: place, date: date, note: trimmedNote, imagesData: imagesData)
                if let linkToTrip {
                    await appModel.linkMemory(memory, to: linkToTrip)
                }
                // Only outside onboarding's mandatory first-memory step (`isDismissable ==
                // false` there) — that flow already has its own dedicated, better-placed
                // invite-partner screen later on, so this would just be a redundant prompt.
                if isDismissable {
                    appModel.noteSoloActionCompleted()
                }
            }
            isSaving = false
            onSaved?()
            dismiss()
        }
    }
}

#Preview {
    AddMemoryView()
        .environment(AppModel())
}
