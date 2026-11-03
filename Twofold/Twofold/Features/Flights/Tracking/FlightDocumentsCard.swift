//
//  FlightDocumentsCard.swift
//  Twofold
//
//  Flight Details' documents: boarding passes, itineraries and the like, attached from the photo
//  library, the camera or Files, and tagged before they upload.
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FlightDocumentsCard: View {
    @Environment(AppModel.self) private var appModel

    let flight: Flight
    /// Loaded by the screen with everything else; added to and removed from here.
    @Binding var documents: [FlightDocument]

    // Document upload. One "+" opens a source menu; whatever comes back is held in
    // `pendingDocumentData` until the traveller says what it is, then uploaded with that tag.
    //
    // The pickers are presented off plain booleans, deliberately. They used to be driven off
    // `FlightDocumentType?` state that doubled as *both* "which kind of document is this" and
    // "is the picker up" — and dismissing a picker sets `isPresented` false, whose setter nil'd
    // that state. So the result handler's `guard let docType` ran against a value the dismissal
    // had already cleared, and both Photo Library and Choose File silently did nothing at all.
    // Nothing now has to survive a dismissal: the type is chosen after the file arrives.
    @State private var showingPhotosPicker = false
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var documentPickerItem: PhotosPickerItem?
    /// A picked file waiting to be tagged. Held rather than uploaded immediately so the tag sheet
    /// can be cancelled without leaving a stray document behind.
    @State private var pendingDocument: PendingFlightDocument?
    @State private var isUploadingDocument = false
    /// Attaching a document had no failure path at all: every step was `try?`-ed and a failure
    /// just meant nothing appeared in the list, which is indistinguishable from the upload still
    /// being in progress. Now the rejections that are the user's to act on say so.
    @State private var documentError: String?

    var body: some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.sm) {
                Text("Documents").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                addDocumentButton
            }

            if documents.isEmpty {
                Text("Boarding passes, itineraries, visas — anything you'll want on the day.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // The rows used to butt straight up against the controls above them. `lg` rather
                // than the card's own default spacing so the heading reads as a heading.
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(FlightDocument.grouped(documents), id: \.label) { group in
                        documentGroup(label: group.label, documents: group.documents)
                    }
                }
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .photosPicker(isPresented: $showingPhotosPicker, selection: $documentPickerItem, matching: .images)
        .onChange(of: documentPickerItem) { _, newItem in
            guard let newItem else { return }
            documentPickerItem = nil
            Task { await stagePickedPhoto(newItem) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(
                onCapture: { image in
                    showingCamera = false
                    stageImage(image, suggestedName: nil)
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                stageFile(at: url)
            }
        }
        .sheet(item: $pendingDocument) { pending in
            NavigationStack {
                FlightDocumentTagSheet(
                    suggestedName: pending.suggestedName,
                    onCancel: { pendingDocument = nil },
                    onConfirm: { docType, customLabel in
                        pendingDocument = nil
                        Task { await upload(pending, docType: docType, customLabel: customLabel) }
                    }
                )
            }
            .presentationDetents([.medium])
        }
        .alert("Couldn't attach that", isPresented: Binding(get: { documentError != nil }, set: { if !$0 { documentError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(documentError ?? "")
        }
    }

    /// One "+", not three cards. The old row asked which *kind* of document you had before it
    /// would let you pick a file, which meant three separate entry points to the same three
    /// pickers, no way to attach two boarding passes without going round twice, and a
    /// "Documents" card whose only label for everything else was the generic "Travel documents".
    private var addDocumentButton: some View {
        Menu {
            Button("Photo library", systemImage: "photo") { showingPhotosPicker = true }
            Button("Take photo", systemImage: "camera") { showingCamera = true }
            Button("Choose file", systemImage: "folder") { showingFileImporter = true }
        } label: {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.15))
                if isUploadingDocument {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 32, height: 32)
        }
        .disabled(isUploadingDocument)
        .accessibilityLabel("Add a document")
    }

    private func documentGroup(label: String, documents: [FlightDocument]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            ForEach(documents) { document in
                SwipeToDeleteRow(
                    onDelete: { Task { await deleteDocument(document) } },
                    accessibilityLabel: "Delete \(document.displayLabel)"
                ) {
                    documentRow(document)
                }
            }
        }
    }

    private func documentRow(_ document: FlightDocument) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            flightDocumentIcon(document.docType.icon, size: 16)
                .foregroundStyle(Theme.accent)
                .frame(width: 18)

            // The filename, not the tag — the tag is the group heading directly above, so a row
            // repeating it says nothing at all (three rows reading "Boarding pass" under a
            // heading reading "Boarding pass"). Camera captures have no filename to show, so
            // those fall back to when they were added, which at least tells them apart.
            Text(document.originalFilename ?? "Added \(document.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: Theme.Spacing.xs)

            if let url = document.url {
                Link("View", destination: url).font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .frame(maxWidth: .infinity)
        .themedCardBackground(cornerRadius: 12)
    }

    /// Renders either a bundled asset (e.g. the boarding-pass glyph, tinted like an SF Symbol
    /// via `.renderingMode(.template)`) or a system symbol, from the same `FlightDocumentIcon`
    /// value — shared between the action cards and the uploaded-documents list row.
    private func flightDocumentIcon(_ icon: FlightDocumentIcon, size: CGFloat) -> some View {
        Group {
            switch icon {
            case .asset(let name):
                Image(name)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            case .system(let name):
                Image(systemName: name)
                    .font(.system(size: size))
            }
        }
    }

    // MARK: - Attaching a document

    private func stagePickedPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            documentError = "Couldn't read that photo. Try picking it again."
            return
        }
        stageImage(image, suggestedName: nil)
    }

    /// Photos and camera captures are resized and re-encoded before they're staged, the same way
    /// they always were — a full-resolution capture is several megabytes against a few hundred
    /// kilobytes, and none of that detail survives being looked at on a phone anyway.
    private func stageImage(_ image: UIImage, suggestedName: String?) {
        guard let jpeg = image.resized(maxDimension: 2000).jpegData(compressionQuality: 0.85) else {
            documentError = "Couldn't prepare that image."
            return
        }
        pendingDocument = PendingFlightDocument(
            data: jpeg, contentType: "image/jpeg", fileExtension: "jpg",
            originalFilename: suggestedName, suggestedName: suggestedName
        )
    }

    /// `FlightDocumentUploadPlan` decides whether a picked file is an image worth re-encoding, a
    /// document to take as-is, or too large to accept at all.
    private func stageFile(at url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            documentError = "Couldn't open that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            documentError = "Couldn't read that file. Try picking it again."
            return
        }

        switch FlightDocumentUploadPlan.plan(for: data) {
        case .recompressImage(let image):
            stageImage(image, suggestedName: url.lastPathComponent)
        case .tooLarge(let bytes, let limit):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            let ceiling = ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)
            documentError = "That file is \(size). Documents need to be under \(ceiling) — try attaching a photo of it instead."
        case .uploadAsIs:
            let fileExtension = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            pendingDocument = PendingFlightDocument(
                data: data,
                contentType: UTType(filenameExtension: fileExtension)?.preferredMIMEType ?? "application/octet-stream",
                fileExtension: fileExtension,
                originalFilename: url.lastPathComponent,
                suggestedName: url.deletingPathExtension().lastPathComponent
            )
        }
    }

    private func upload(_ pending: PendingFlightDocument, docType: FlightDocumentType, customLabel: String?) async {
        isUploadingDocument = true
        defer { isUploadingDocument = false }
        do {
            let document = try await BackendService.insertFlightDocument(
                coupleID: appModel.couple.id, flightID: flight.id, tripID: nil,
                docType: docType, data: pending.data, contentType: pending.contentType,
                fileExtension: pending.fileExtension, originalFilename: pending.originalFilename,
                customLabel: customLabel
            )
            documents.insert(document, at: 0)
        } catch {
            // Told apart, because the advice is opposite. A refusal means the subscription, and
            // "check your connection and try again" sends somebody to look at their wifi forever
            // over something retrying will never fix.
            documentError = BackendService.isPermanentRefusal(error)
                ? "Adding documents needs an active subscription. Nothing was uploaded."
                : "Couldn't upload that document. Check your connection and try again."
        }
    }

    private func deleteDocument(_ document: FlightDocument) async {
        // Removed from the list first: the row is already gone under the finger that swiped it,
        // and putting it back on a network hiccup reads worse than leaving it deleted.
        documents.removeAll { $0.id == document.id }
        try? await BackendService.deleteFlightDocument(id: document.id, path: document.filePath)
    }
}
