//
//  AddMemoryView.swift
//  Twofold
//

import SwiftUI
import PhotosUI

struct AddMemoryView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    private static let emojiOptions = ["💛", "📍", "✈️", "🌅", "🍜", "🎉", "🏖️", "🎂"]

    @State private var title: String = ""
    @State private var place: Place?
    @State private var date: Date = .now
    @State private var emoji: String = "💛"
    @State private var note: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var previewImage: Image?
    @State private var imageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && place != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            OnboardingScaffold(
                title: "Add a memory",
                subtitle: "Keep a moment from this trip or place.",
                content: {
                    VStack(spacing: Theme.Spacing.md) {
                        photoPicker

                        TextField("Title", text: $title)
                            .textFieldStyle()

                        CityMenuPicker(label: "Where", selection: $place)

                        DatePicker("When", selection: $date, in: ...Date.now, displayedComponents: .date)
                            .padding()
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                        emojiPicker

                        TextEditor(text: $note)
                            .frame(height: 100)
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Spacing.sm)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(Theme.heartRed)
                        }
                    }
                },
                primaryTitle: "Save memory",
                primaryAction: save,
                primaryDisabled: !canSave
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $selectedItem, matching: .images) {
            ZStack {
                if let previewImage {
                    previewImage.resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.cardBackground)
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title2)
                        Text("Add a photo").font(.caption)
                    }
                    .foregroundStyle(Theme.subtleInk)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Emoji").font(.caption).foregroundStyle(Theme.subtleInk)
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(Self.emojiOptions, id: \.self) { option in
                    Button {
                        emoji = option
                    } label: {
                        Text(option)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(Theme.cardBackground, in: Circle())
                            .overlay(
                                Circle().strokeBorder(emoji == option ? Theme.skyBlue : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { return }
            let resized = uiImage.resized(maxDimension: 1024)
            imageData = resized.jpegData(compressionQuality: 0.8)
            previewImage = Image(uiImage: resized)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let place else { return }
        isSaving = true
        errorMessage = nil
        Task {
            await appModel.addMemory(
                title: title.trimmingCharacters(in: .whitespaces),
                place: place,
                date: date,
                emoji: emoji,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                imageData: imageData
            )
            isSaving = false
            dismiss()
        }
    }
}

private extension View {
    func textFieldStyle() -> some View {
        self
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

#Preview {
    AddMemoryView()
        .environment(AppModel())
}
