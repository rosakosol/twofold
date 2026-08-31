//
//  FlightDocument.swift
//  Twofold
//

import Foundation
import UIKit

enum FlightDocumentIcon: Hashable {
    case system(String)
    case asset(String)

    var name: String {
        switch self {
        case .system(let name), .asset(let name):
            return name
        }
    }
}

enum FlightDocumentType: String, Codable, CaseIterable, Hashable {
    case boardingPass = "boarding_pass"
    case itinerary
    case other

    var label: String {
        switch self {
        case .boardingPass:
            return "Boarding pass"
        case .itinerary:
            return "Itinerary"
        case .other:
            // Catch-all for anything that isn't a boarding pass or itinerary specifically —
            // visa documents, travel insurance, hotel confirmations, etc.
            return "Travel documents"
        }
    }

    var icon: FlightDocumentIcon {
        switch self {
        case .boardingPass:
            return .asset("boarding-pass")      // Your Assets.xcassets image
        case .itinerary:
            return .system("doc.text.fill")
        case .other:
            return .system("paperclip")
        }
    }
}

struct FlightDocument: Identifiable, Hashable {
    let id: UUID
    var flightID: UUID?
    var tripID: UUID?
    var uploadedBy: UUID
    var docType: FlightDocumentType
    var filePath: String
    var originalFilename: String?
    var contentType: String?
    /// The traveller's own name for an `.other` document — a visa, travel insurance, a hotel
    /// confirmation. Nil for boarding passes and itineraries, which carry their own fixed names.
    var customLabel: String?
    var createdAt: Date
    var url: URL?

    init(
        id: UUID = UUID(),
        flightID: UUID? = nil,
        tripID: UUID? = nil,
        uploadedBy: UUID,
        docType: FlightDocumentType,
        filePath: String,
        originalFilename: String? = nil,
        contentType: String? = nil,
        customLabel: String? = nil,
        createdAt: Date = .now,
        url: URL? = nil
    ) {
        self.id = id
        self.flightID = flightID
        self.tripID = tripID
        self.uploadedBy = uploadedBy
        self.docType = docType
        self.filePath = filePath
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.customLabel = customLabel
        self.createdAt = createdAt
        self.url = url
    }
}

extension FlightDocument {
    /// What this document is called on screen. A custom label when the traveller gave one,
    /// otherwise the type's own fixed name.
    var displayLabel: String { customLabel?.trimmed.nilIfEmpty ?? docType.label }

    /// Documents sharing a heading, in the order they should be listed. Grouped by what they're
    /// *called* rather than by `docType`, so two custom-named documents ("Visa", "Insurance")
    /// don't collapse into one "Travel documents" pile the way they would under a raw type key —
    /// which was the point of letting them be named at all.
    static func grouped(_ documents: [FlightDocument]) -> [(label: String, documents: [FlightDocument])] {
        var order: [String] = []
        var byLabel: [String: [FlightDocument]] = [:]
        for document in documents {
            let label = document.displayLabel
            if byLabel[label] == nil { order.append(label) }
            byLabel[label, default: []].append(document)
        }
        return order.map { ($0, byLabel[$0] ?? []) }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// What to do with a file someone picked through Files, decided before any upload happens so it
/// can be tested without a picker, a network or a view.
///
/// The Photos and camera buttons have always resized and re-encoded what they capture. The Files
/// button didn't, so the same photo went up at full capture resolution — several megabytes against
/// a few hundred kilobytes — decided purely by which menu item was tapped.
enum FlightDocumentUploadPlan {
    /// Re-encode through the same path the Photos button uses.
    case recompressImage(UIImage)
    /// Not an image, so it can't be made smaller without destroying it. Upload the bytes as they are.
    case uploadAsIs
    /// Not an image and past the ceiling. Nothing sensible to do but say so.
    case tooLarge(bytes: Int, limit: Int)

    /// The ceiling for a file that can't be re-encoded smaller. Boarding passes and itineraries sit
    /// comfortably under a megabyte; past this it's a scanned brochure, and spending the couple's
    /// storage on it silently is worse than declining.
    static let defaultLimit = 10 * 1024 * 1024

    /// Decided by decoding, not by file extension — a picked file may carry none, or a misleading
    /// one, and what matters is whether the bytes can be re-encoded, not what they're called.
    static func plan(for data: Data, limit: Int = defaultLimit) -> FlightDocumentUploadPlan {
        if let image = UIImage(data: data) { return .recompressImage(image) }
        if data.count > limit { return .tooLarge(bytes: data.count, limit: limit) }
        return .uploadAsIs
    }
}
