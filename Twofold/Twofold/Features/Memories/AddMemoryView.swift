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

    @State private var title: String
    @State private var place: Place?
    @State private var date: Date
    @State private var note: String
    @State private var existingPhotos: [MemoryPhoto]

    @State private var pendingPhotos: [PendingPhoto] = []
    @State private var loadedItemKeys: Set<String> = []
    @State private var selectedItems: [PhotosPickerItem] = []

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingLocationSearch = false
    @State private var locationService = HomeLocationService()
    @State private var mapCameraPosition: MapCameraPosition

    private enum Field: Hashable { case title, note }
    /// Drives both the keyboard's "Done" accessory and the map's shrink-while-editing-notes
    /// behavior below — the map used to stay fixed at half the screen even with the keyboard up,
    /// leaving barely any room to actually see what you were typing in the notes field.
    @FocusState private var focusedField: Field?

    private struct PendingPhoto: Identifiable {
        let id = UUID()
        var image: Image
        var data: Data
    }

    init(existingMemory: Memory? = nil, isDismissable: Bool = true) {
        self.existingMemory = existingMemory
        self.isDismissable = isDismissable
        _title = State(initialValue: existingMemory?.title ?? "")
        _place = State(initialValue: existingMemory?.place)
        _date = State(initialValue: existingMemory?.date ?? .now)
        _note = State(initialValue: existingMemory?.note ?? "")
        _existingPhotos = State(initialValue: existingMemory?.photos ?? [])
        _mapCameraPosition = State(initialValue: existingMemory?.place.map {
            .region(MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 4000, longitudinalMeters: 4000))
        } ?? .automatic)
    }

    private var isEditing: Bool { existingMemory != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    locationMap
                        .frame(height: focusedField == .note ? geo.size.height * 0.15 : geo.size.height / 2)
                        .animation(.easeInOut(duration: 0.25), value: focusedField)

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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
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
            .onChange(of: selectedItems) { _, newItems in
                Task { await loadNewPhotos(newItems) }
            }
            .sheet(isPresented: $showingLocationSearch) {
                MemoryLocationSearchView { selected in place = selected }
            }
            .sheet(isPresented: $showingDatePicker) { datePickerSheet }
            .sheet(isPresented: $showingTimePicker) { timePickerSheet }
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
            Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                .font(.subheadline)
                .foregroundStyle(Theme.subtleInk)
            if let place {
                Text(place.city)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
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
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .focused($focusedField, equals: .note)
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(existingPhotos) { photo in
                    ZStack(alignment: .topTrailing) {
                        ExistingPhotoThumbnail(photo: photo)
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
        .padding(4)
    }

    private var bottomBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            PhotosPicker(selection: $selectedItems, maxSelectionCount: 8, matching: .images) {
                iconCircle("photo.badge.plus")
            }
            Button { showingDatePicker = true } label: { iconCircle("calendar") }
            Button { showingTimePicker = true } label: { iconCircle("clock") }
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

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Date", selection: dateOnlyBinding, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("When")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private var timePickerSheet: some View {
        NavigationStack {
            DatePicker("Time", selection: timeOnlyBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle("What time?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingTimePicker = false }
                    }
                }
        }
        .presentationDetents([.height(300)])
    }

    /// Writes the picked calendar day into `date` while preserving whatever time-of-day is
    /// already set (and vice versa for `timeOnlyBinding`) — the two pickers edit the same
    /// underlying `Date` independently, the way separate date/time icons imply they should.
    private var dateOnlyBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newValue in
                let calendar = Calendar.current
                let time = calendar.dateComponents([.hour, .minute], from: date)
                var components = calendar.dateComponents([.year, .month, .day], from: newValue)
                components.hour = time.hour
                components.minute = time.minute
                date = calendar.date(from: components) ?? newValue
            }
        )
    }

    private var timeOnlyBinding: Binding<Date> {
        Binding(
            get: { date },
            set: { newValue in
                let calendar = Calendar.current
                let time = calendar.dateComponents([.hour, .minute], from: newValue)
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = time.hour
                components.minute = time.minute
                date = calendar.date(from: components) ?? newValue
            }
        )
    }

    private func removeExistingPhoto(_ photo: MemoryPhoto) {
        existingPhotos.removeAll { $0.id == photo.id }
        guard let existingMemory else { return }
        Task { await appModel.removePhoto(photo, from: existingMemory) }
    }

    /// `loadTransferable` is known to fail intermittently — most visibly in the Simulator, where
    /// PHPickerViewController's out-of-process data handoff for seeded library assets frequently
    /// times out. A failed item deliberately isn't added to `loadedItemKeys`, so it gets another
    /// attempt the next time this runs (e.g. picking one more photo re-fires `onChange` with the
    /// whole selection) instead of being silently dropped forever with no way to retry it short
    /// of restarting the picker from scratch.
    ///
    /// Every item's load + decode + downscale + JPEG-encode runs concurrently via a `TaskGroup` —
    /// this used to be a plain sequential loop, so picking the full 8-photo selection meant eight
    /// full decode/resize/encode passes back to back (each one a real CPU cost on a full-resolution
    /// source photo) before the last thumbnail ever appeared. Only the final bookkeeping
    /// (`loadedItemKeys`/`pendingPhotos`/`errorMessage`) touches view state, and only after every
    /// task has finished, same shape as `BackendService`'s photo-signing TaskGroup.
    private func loadNewPhotos(_ items: [PhotosPickerItem]) async {
        let itemsToLoad = items
            .map { ($0, $0.itemIdentifier ?? UUID().uuidString) }
            .filter { !loadedItemKeys.contains($0.1) }
        guard !itemsToLoad.isEmpty else { return }

        let results = await withTaskGroup(of: (String, PendingPhoto?).self) { group in
            for (item, key) in itemsToLoad {
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let uiImage = UIImage(data: data) else { return (key, nil) }
                    let resized = uiImage.resized(maxDimension: 1600)
                    guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return (key, nil) }
                    return (key, PendingPhoto(image: Image(uiImage: resized), data: jpeg))
                }
            }
            var collected: [(String, PendingPhoto?)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var failedCount = 0
        for (key, pending) in results {
            if let pending {
                loadedItemKeys.insert(key)
                pendingPhotos.append(pending)
            } else {
                failedCount += 1
            }
        }
        if failedCount > 0 {
            errorMessage = failedCount == 1
                ? "Couldn't load that photo — try selecting it again."
                : "Couldn't load \(failedCount) of those photos — try selecting them again."
        }
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
                await appModel.addMemory(title: trimmedTitle, place: place, date: date, note: trimmedNote, imagesData: imagesData)
            }
            isSaving = false
            dismiss()
        }
    }
}

/// An already-uploaded photo's thumbnail (as opposed to a `pendingPhotos` entry, which is backed
/// by local `Data` and needs no loading at all). Shares `MemoryPhotoView`'s path-keyed
/// `MemoryPhotoImageCache` rather than plain `AsyncImage`, so re-opening this sheet for the same
/// memory — or the same photo appearing again in the Memories list/Relationship Stats snapshot —
/// resolves instantly from cache instead of re-downloading.
private struct ExistingPhotoThumbnail: View {
    let photo: MemoryPhoto

    @State private var loadedImage: UIImage?

    private var cacheKey: String { photo.path == "pending" ? photo.url.absoluteString : photo.path }
    private var resolvedImage: UIImage? { loadedImage ?? MemoryPhotoImageCache.shared.image(for: cacheKey) }

    var body: some View {
        Group {
            if let resolvedImage {
                Image(uiImage: resolvedImage).resizable().scaledToFill()
            } else {
                Theme.cardBackground
                    .task(id: cacheKey) { await load() }
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

#Preview {
    AddMemoryView()
        .environment(AppModel())
}
