//
//  FlightDocument.swift
//  Twofold
//

import Foundation

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
        self.createdAt = createdAt
        self.url = url
    }
}
