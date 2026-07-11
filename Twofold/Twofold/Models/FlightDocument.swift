//
//  FlightDocument.swift
//  Twofold
//
//  Boarding passes / travel documents attached to a flight or a linked trip — user-uploaded,
//  clearly distinct from live provider data. Mirrors the `MemoryPhoto` pattern: private
//  storage, signed URL resolved on fetch.
//

import Foundation

enum FlightDocumentType: String, Codable, CaseIterable, Hashable {
    case boardingPass = "boarding_pass"
    case itinerary
    case other

    var label: String {
        switch self {
        case .boardingPass: "Boarding pass"
        case .itinerary: "Travel documents"
        case .other: "Document"
        }
    }

    var icon: String {
        switch self {
        case .boardingPass: "ticket.fill"
        case .itinerary: "doc.text.fill"
        case .other: "paperclip"
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
