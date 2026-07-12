//
//  AddMemoryView.swift
//  Twofold
//

import SwiftUI
import PhotosUI

struct AddMemoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private let existingMemory: Memory?

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

    private struct PendingPhoto: Identifiable {
        let id = UUID()
        var image: Image
        var data: Data
    }

    init(existingMemory: Memory? = nil) {
        self.existingMemory = existingMemory
        _title = State(initialValue: existingMemory?.title ?? "")
        _place = State(initialValue: existingMemory?.place)
        _date = State(initialValue: existingMemory?.date ?? .now)
        _note = State(initialValue: existingMemory?.note ?? "")
        _existingPhotos = State(initialValue: existingMemory?.photos ?? [])
    }

    private var isEditing: Bool { existingMemory != nil }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // New memories default to the user's own home city — location is required to
                // save, so this means most people never have to think about it, while still
                // leaving it changeable for a memory made somewhere else.
                if !isEditing, place == nil {
                    place = appModel.currentUser.homeCity
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
    }

    private var titleRow: some View {
        TextField("Memory title", text: $title)
            .font(.title2.weight(.bold))
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
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(existingPhotos) { photo in
                    photoThumbnail(url: photo.url) { removeExistingPhoto(photo) }
                }
                ForEach(pendingPhotos) { pending in
                    photoThumbnail(image: pending.image) {
                        pendingPhotos.removeAll { $0.id == pending.id }
                    }
                }
            }
        }
    }

    private func photoThumbnail(url: URL, remove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Theme.cardBackground
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            removeButton(action: remove)
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

    private func loadNewPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            let key = item.itemIdentifier ?? UUID().uuidString
            guard !loadedItemKeys.contains(key) else { continue }
            loadedItemKeys.insert(key)
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { continue }
            let resized = uiImage.resized(maxDimension: 1600)
            guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { continue }
            pendingPhotos.append(PendingPhoto(image: Image(uiImage: resized), data: jpeg))
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

#Preview {
    AddMemoryView()
        .environment(AppModel())
}
