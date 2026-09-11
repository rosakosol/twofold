//
//  RelationshipTimelineView.swift
//  Twofold
//
//  The relationship record, as something you scroll rather than something you download.
//
//  Same items the PDF and the Word export are built from — see `RelationshipRecord.timeline`, which
//  exists so these three cannot tell different stories about the same couple. Exporting is one
//  action on this screen rather than the point of it: the document is a copy of what is already
//  here, not a thing you have to generate before you can look at it.
//
//  Reads trips, memories and flights straight from `AppModel` rather than fetching. They are
//  already loaded — this screen is reachable only from Settings, several screens deep into a
//  running app — and a spinner in front of data the app is holding would be theatre.
//

import PostHog
import SwiftUI

struct RelationshipTimelineView: View {
    @Environment(AppModel.self) private var appModel

    @State private var exportURL: ExportedDocument?
    @State private var isExporting = false
    @State private var exportStatus = ""
    @State private var exportError: String?

    /// A finished file, identified so `.sheet(item:)` presents it once it exists rather than being
    /// driven off a separate boolean that can disagree with it.
    private struct ExportedDocument: Identifiable {
        let id = UUID()
        let url: URL
    }

    private var items: [ExportTimelineItem] {
        RelationshipRecord.timeline(
            trips: appModel.trips,
            memories: appModel.memories,
            flights: appModel.flights
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if items.isEmpty {
                    emptyState
                } else {
                    header
                    ForEach(items) { item in
                        TimelineEntryView(item: item)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Our Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { export(.pdf) } label: { Label("Export as PDF", systemImage: "doc.richtext") }
                        Button { export(.word) } label: { Label("Export as Word", systemImage: "doc.text") }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                }
            }
        }
        .sheet(item: $exportURL) { document in
            ExportReadySheet(url: document.url)
        }
        .overlay(alignment: .bottom) {
            if isExporting || exportError != nil {
                statusBar
            }
        }
        .postHogScreenView("Settings: Relationship Timeline")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("\(items.count) \(items.count == 1 ? "moment" : "moments") together")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Every trip, memory and flight you've shared, in the order it happened.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
        }
    }

    private var emptyState: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Your story starts here")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Add a trip, save a memory or track a flight, and it'll appear here in order.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var statusBar: some View {
        Text(exportError ?? exportStatus)
            .font(.caption)
            .foregroundStyle(exportError == nil ? Theme.subtleInk : Theme.heartRed)
            .padding(Theme.Spacing.sm)
            .background(Theme.cardBackground, in: Capsule())
            .padding(.bottom, Theme.Spacing.md)
    }

    private enum Format { case pdf, word }

    private func export(_ format: Format) {
        isExporting = true
        exportError = nil
        exportStatus = "Preparing…"
        Task {
            defer { isExporting = false }
            let url: URL?
            switch format {
            case .pdf:
                url = await CoupleDataExporter.relationshipRecordPDF(
                    coupleID: appModel.couple.id,
                    selfName: appModel.currentUser.name,
                    partnerName: appModel.partner.name,
                    selfPhotoURL: appModel.currentUser.avatarURL,
                    partnerPhotoURL: appModel.partner.avatarURL,
                    progress: { exportStatus = $0 }
                )
            case .word:
                exportStatus = "Writing your record…"
                url = await RelationshipRecordWriter.rtf(
                    items: items,
                    selfName: appModel.currentUser.name,
                    partnerName: appModel.partner.name
                )
            }
            if let url {
                exportURL = ExportedDocument(url: url)
            } else {
                exportError = "Couldn't build that file. Try again."
            }
        }
    }
}

/// One entry. A trip brings its own flights and memories with it — see
/// `RelationshipRecord.timeline` for why they are not separate entries.
private struct TimelineEntryView: View {
    let item: ExportTimelineItem

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(Theme.skyBlue)
                    Text(kind.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Theme.subtleInk)
                    Spacer()
                    Text(item.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(photoGroups, id: \.0) { memoryID, photos in
                    PhotoPager(photos: photos)
                        .id(memoryID)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var kind: String {
        switch item {
        case .trip: "Trip"
        case .memory: "Memory"
        case .flight: "Flight"
        }
    }

    private var icon: String {
        switch item {
        case .trip: "suitcase.fill"
        case .memory: "heart.fill"
        case .flight: "airplane"
        }
    }

    private var title: String {
        switch item {
        case .trip(let trip, _, _, _): "\(trip.origin.displayCity) → \(trip.destination.displayCity)"
        case .memory(let memory, _): memory.title.isEmpty ? "A moment" : memory.title
        case .flight(let flight, _, _): RelationshipRecordWriter.flightRoute(flight)
        }
    }

    private var subtitle: String {
        switch item {
        case .trip(_, let description, let flights, let memories):
            var parts: [String] = []
            if !description.isEmpty { parts.append(description) }
            if !flights.isEmpty { parts.append("\(flights.count) \(flights.count == 1 ? "flight" : "flights")") }
            if !memories.isEmpty { parts.append("\(memories.count) \(memories.count == 1 ? "memory" : "memories")") }
            return parts.joined(separator: " · ")
        case .memory(_, let description): return description
        case .flight(let flight, _, _): return flight.displayNumber
        }
    }

    /// Every set of photos this entry carries, keyed by the memory they belong to — a trip's
    /// memories keep their own groups rather than being poured into one strip, so swiping through
    /// one afternoon never runs into another.
    private var photoGroups: [(UUID, [MemoryPhoto])] {
        switch item {
        case .memory(let memory, _):
            return memory.photos.isEmpty ? [] : [(memory.id, memory.photos)]
        case .trip(_, _, _, let memories):
            return memories.compactMap { linked in
                linked.memory.photos.isEmpty ? nil : (linked.memory.id, linked.memory.photos)
            }
        case .flight:
            return []
        }
    }
}

/// Swipeable photos for one memory.
///
/// `TabView`'s page style rather than a horizontal `ScrollView`: it brings the dots, the paging
/// stops and the accessibility behaviour with it, and a strip that free-scrolls between two
/// photos is the thing people complain about in every app that builds this by hand.
private struct PhotoPager: View {
    let photos: [MemoryPhoto]
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                AsyncImage(url: photo.url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Theme.cardBackground
                }
                .clipped()
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.sm, style: .continuous))
        .accessibilityLabel(
            photos.count == 1 ? "1 photo" : "\(photos.count) photos, swipe to see more"
        )
    }
}

/// Presented once a file exists, holding the `ShareLink` that hands it over.
///
/// A sheet rather than a `UIActivityViewController` wrapper: every other share in this app goes
/// through `ShareLink`, and that button cannot be triggered programmatically — so the export
/// finishing has to present something that contains one, rather than presenting the share sheet
/// itself.
///
/// Laid out as `ReviewPromptView` is, which is this app's shape for a peek sheet: a glyph, a
/// headline and a subheadline centred, one filled capsule action, a plain dismiss under it, and
/// the background gradient rather than the system's default sheet ground. A fixed height rather
/// than `.medium`, for the same reason that one does — the content is a known size, and `.medium`
/// leaves half a screen of empty gradient under four lines of text.
private struct ExportReadySheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text("📖").font(.system(size: 48))

            VStack(spacing: Theme.Spacing.xs) {
                Text("Your record is ready")
                    .font(.headline)
                Text(url.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.sm) {
                ShareLink(item: url, preview: SharePreview("Our Story", image: Image(systemName: "book.closed"))) {
                    Text("Save or Share")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background(Theme.primaryButtonGradient, in: Capsule())
                .foregroundStyle(.white)

                Button("Not Right Now") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding(.horizontal, Theme.Spacing.lg)
        }
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(300)])
    }
}
