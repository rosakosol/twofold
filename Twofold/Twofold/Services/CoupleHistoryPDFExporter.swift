//
//  CoupleHistoryPDFExporter.swift
//  Twofold
//
//  Renders a selected, chronologically-ordered set of trips/memories/flights into a single
//  formatted PDF — a cover page, then one page per item. Establishes a new pattern for this
//  codebase (every existing `ImageRenderer` use produces one shareable `Image` — see
//  `DistanceShareView`/`GameResultsShareView` — never a multi-page file): each page is a
//  fixed-size SwiftUI view rasterized via `ImageRenderer`, then wrapped as a single-page PDF and
//  appended into a master `PDFDocument`. PDF-format flight attachments are spliced in as their
//  own real pages (not flattened to an image) via `PDFDocument.insert(_:at:)`, immediately after
//  the flight page that owns them — building the whole document incrementally, in final order,
//  avoids ever needing to reorder pages after the fact.
//

import SwiftUI
import PDFKit

/// One selected, exportable entry — built by `ExportHistoryView` from the user's selections.
/// `date` drives the single chronological ordering across all three kinds combined.
enum ExportTimelineItem: Identifiable {
    case trip(Trip, description: String)
    case memory(Memory, description: String)
    case flight(Flight, includeAttachments: Bool, attachments: [FlightDocument])

    var id: String {
        switch self {
        case .trip(let trip, _): "trip-\(trip.id)"
        case .memory(let memory, _): "memory-\(memory.id)"
        case .flight(let flight, _, _): "flight-\(flight.id)"
        }
    }

    var date: Date {
        switch self {
        case .trip(let trip, _): trip.departureDate
        case .memory(let memory, _): memory.date
        case .flight(let flight, _, _): flight.bestDeparture ?? .distantPast
        }
    }
}

enum CoupleHistoryPDFExporter {
    enum ExportError: Error {
        case renderingFailed
    }

    /// US Letter at 72pt/inch — the standard `UIGraphicsPDFRenderer` page size.
    private static let pageSize = CGRect(x: 0, y: 0, width: 612, height: 792)

    @MainActor
    static func generate(
        selfName: String,
        partnerName: String,
        selfPhotoURL: URL?,
        partnerPhotoURL: URL?,
        items: [ExportTimelineItem]
    ) async throws -> URL {
        let sorted = items.sorted { $0.date < $1.date }
        let dateRange = dateRangeLabel(for: sorted)
        let master = PDFDocument()

        func append(_ image: UIImage) {
            guard let page = pdfPage(from: image) else { return }
            master.insert(page, at: master.pageCount)
        }

        let selfPhoto = await downloadImage(from: selfPhotoURL)
        let partnerPhoto = await downloadImage(from: partnerPhotoURL)
        append(renderPage(CoverPageView(selfName: selfName, partnerName: partnerName, selfPhoto: selfPhoto, partnerPhoto: partnerPhoto, dateRange: dateRange, itemCount: sorted.count)))

        for item in sorted {
            switch item {
            case .trip(let trip, let description):
                append(renderPage(TripPageView(trip: trip, description: description)))

            case .memory(let memory, let description):
                let photo = await downloadImage(from: memory.photoURL)
                append(renderPage(MemoryPageView(memory: memory, description: description, photo: photo)))

            case .flight(let flight, let includeAttachments, let attachments):
                let logo = await downloadImage(from: flight.displayLogoURL)
                append(renderPage(FlightPageView(flight: flight, logo: logo)))
                guard includeAttachments else { continue }
                for attachment in attachments {
                    await appendAttachment(attachment, into: master, append: append)
                }
            }
        }

        guard let finalData = master.dataRepresentation() else {
            throw ExportError.renderingFailed
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Our Story.pdf")
        try finalData.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Attachments

    /// PDF attachments splice their real pages straight into `master` (multi-page boarding
    /// passes/itineraries stay intact); image attachments render as their own full page via the
    /// same `ImageRenderer` path every other page uses.
    private static func appendAttachment(_ attachment: FlightDocument, into master: PDFDocument, append: (UIImage) -> Void) async {
        guard let url = attachment.url else { return }
        if attachment.contentType == "application/pdf" {
            guard let (data, _) = try? await URLSession.shared.data(from: url), let attachmentDoc = PDFDocument(data: data) else { return }
            for pageIndex in 0..<attachmentDoc.pageCount {
                guard let page = attachmentDoc.page(at: pageIndex) else { continue }
                master.insert(page, at: master.pageCount)
            }
        } else if let image = await downloadImage(from: url) {
            append(renderPage(AttachmentImagePageView(attachment: attachment, image: image)))
        }
    }

    // MARK: - Page rendering

    @MainActor
    private static func renderPage<Content: View>(_ content: Content) -> UIImage {
        let renderer = ImageRenderer(content: content.frame(width: pageSize.width, height: pageSize.height))
        renderer.scale = 2
        return renderer.uiImage ?? UIImage()
    }

    /// Wraps one rasterized page image as a single-page PDF, then hands back the resulting
    /// `PDFPage` for insertion into the master document — `UIGraphicsPDFRenderer` itself only
    /// knows how to build a whole PDF top-to-bottom, not one page in isolation, so this is the
    /// smallest unit it can produce.
    private static func pdfPage(from image: UIImage) -> PDFPage? {
        let renderer = UIGraphicsPDFRenderer(bounds: pageSize)
        let data = renderer.pdfData { context in
            context.beginPage()
            image.draw(in: pageSize)
        }
        return PDFDocument(data: data)?.page(at: 0)
    }

    // MARK: - Shared helpers

    private static func downloadImage(from url: URL?) async -> UIImage? {
        guard let url else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return UIImage(data: data)
    }

    private static func dateRangeLabel(for items: [ExportTimelineItem]) -> String {
        guard let first = items.first?.date, let last = items.last?.date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        if Calendar.current.isDate(first, equalTo: last, toGranularity: .month) {
            return formatter.string(from: first)
        }
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }
}

// MARK: - Page layouts
//
// Pure rendering views, never shown live on-screen — offscreen-only content for
// `CoupleHistoryPDFExporter.renderPage(_:)` to rasterize. Visual language matches the app's
// existing shareable cards (`DistanceSnapshotCard`'s serif "twofold" wordmark, `Theme` colors/
// spacing/radius) rather than a plain data dump.

private let coupleHistoryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMMM yyyy"
    return formatter
}()

private let coupleHistoryDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMMM yyyy, h:mm a"
    return formatter
}()

private struct CoverPageView: View {
    let selfName: String
    let partnerName: String
    let selfPhoto: UIImage?
    let partnerPhoto: UIImage?
    let dateRange: String
    let itemCount: Int

    var body: some View {
        ZStack {
            Theme.backgroundGradient

            VStack(spacing: Theme.Spacing.xl) {
                Spacer()

                HStack(spacing: Theme.Spacing.lg) {
                    avatar(selfPhoto, tint: Theme.skyBlue)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.heartRed)
                    avatar(partnerPhoto, tint: Theme.heartRed)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Text("Our Story")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("\(selfName) & \(partnerName)")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(Theme.subtleInk)
                    if !dateRange.isEmpty {
                        Text(dateRange)
                            .font(.headline)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    Text("\(itemCount) \(itemCount == 1 ? "moment" : "moments") together")
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                }

                Spacer()

                Text("twofold")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Theme.subtleInk.opacity(0.6))
            }
            .padding(60)
        }
    }

    private func avatar(_ photo: UIImage?, tint: Color) -> some View {
        ZStack {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Circle().fill(tint)
                Image(systemName: "person.fill").font(.title).foregroundStyle(.white)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
}

/// Shared header (kind icon/label + date), title, and footer wordmark every story page uses —
/// only the content in between differs per kind.
private struct StoryPageChrome<Content: View>: View {
    let kindLabel: String
    let kindIcon: String
    let dateText: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: kindIcon)
                    .foregroundStyle(Theme.skyBlue)
                Text(kindLabel.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Theme.subtleInk)
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding(.bottom, Theme.Spacing.sm)

            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, Theme.Spacing.lg)

            content

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text("twofold")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Theme.subtleInk.opacity(0.5))
                Spacer()
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

private struct TripPageView: View {
    let trip: Trip
    let description: String

    var body: some View {
        StoryPageChrome(
            kindLabel: trip.isReunionTrip ? "Reunion Trip" : "Trip",
            kindIcon: "airplane",
            dateText: coupleHistoryDateFormatter.string(from: trip.departureDate),
            title: "\(trip.origin.displayCity) → \(trip.destination.displayCity)"
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                routeCard
                ForEach(trip.orderedFlights) { flight in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "airplane.circle.fill").foregroundStyle(Theme.skyBlue)
                        Text("\(flight.displayNumber)\(flight.airlineName.map { " · \($0)" } ?? "")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                if !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(4)
                }
            }
        }
    }

    private var routeCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.origin.displayCity).font(.headline)
                Text(coupleHistoryDateFormatter.string(from: trip.departureDate)).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(Theme.subtleInk)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(trip.destination.displayCity).font(.headline)
                Text(coupleHistoryDateFormatter.string(from: trip.arrivalDate)).font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

private struct MemoryPageView: View {
    let memory: Memory
    let description: String
    let photo: UIImage?

    var body: some View {
        StoryPageChrome(
            kindLabel: "Memory",
            kindIcon: "heart.fill",
            dateText: coupleHistoryDateFormatter.string(from: memory.date),
            title: memory.title
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 280)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                if let place = memory.place {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.heartRed)
                        Text(place.displayCity).font(.subheadline).foregroundStyle(Theme.subtleInk)
                    }
                }
                if !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(4)
                }
            }
        }
    }
}

private struct FlightPageView: View {
    let flight: Flight
    let logo: UIImage?

    var body: some View {
        StoryPageChrome(
            kindLabel: "Flight",
            kindIcon: "airplane",
            dateText: flight.bestDeparture.map { coupleHistoryDateTimeFormatter.string(from: $0) } ?? "",
            title: "\(flight.origin.displayCode) → \(flight.destination.displayCode)"
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    if let logo {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flight.displayNumber).font(.headline)
                        if let airlineName = flight.airlineName {
                            Text(airlineName).font(.caption).foregroundStyle(Theme.subtleInk)
                        }
                    }
                }
                routeCard
            }
        }
    }

    private var routeCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.origin.displayCode).font(.title3.weight(.bold))
                Text(flight.origin.displayName).font(.caption).foregroundStyle(Theme.subtleInk)
                if let departure = flight.bestDeparture {
                    Text(coupleHistoryDateTimeFormatter.string(from: departure)).font(.caption2).foregroundStyle(Theme.subtleInk)
                }
            }
            Spacer()
            Image(systemName: "airplane").foregroundStyle(Theme.skyBlue)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(flight.destination.displayCode).font(.title3.weight(.bold))
                Text(flight.destination.displayName).font(.caption).foregroundStyle(Theme.subtleInk)
                if let arrival = flight.bestArrival {
                    Text(coupleHistoryDateTimeFormatter.string(from: arrival)).font(.caption2).foregroundStyle(Theme.subtleInk)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

private struct AttachmentImagePageView: View {
    let attachment: FlightDocument
    let image: UIImage

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(attachment.docType.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.subtleInk)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("twofold")
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(Theme.subtleInk.opacity(0.5))
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}
