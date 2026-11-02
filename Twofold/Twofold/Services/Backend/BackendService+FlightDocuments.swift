//
//  BackendService+FlightDocuments.swift
//  Twofold
//
//  Boarding passes and travel documents attached to a flight or trip.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Flight documents (boarding passes / travel docs)

    private struct FlightDocumentRow: Decodable {
        var id: UUID
        var flightId: UUID?
        var tripId: UUID?
        var uploadedBy: UUID
        var docType: FlightDocumentType
        var filePath: String
        var originalFilename: String?
        var contentType: String?
        var customLabel: String?
        var createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case flightId = "flight_id"
            case tripId = "trip_id"
            case uploadedBy = "uploaded_by"
            case docType = "doc_type"
            case filePath = "file_path"
            case originalFilename = "original_filename"
            case contentType = "content_type"
            case customLabel = "custom_label"
            case createdAt = "created_at"
        }
    }

    private struct FlightDocumentInsert: Encodable {
        var flightId: UUID?
        var tripId: UUID?
        var uploadedBy: UUID
        var docType: String
        var filePath: String
        var originalFilename: String?
        var contentType: String?
        var customLabel: String?

        enum CodingKeys: String, CodingKey {
            case flightId = "flight_id"
            case tripId = "trip_id"
            case uploadedBy = "uploaded_by"
            case docType = "doc_type"
            case filePath = "file_path"
            case originalFilename = "original_filename"
            case contentType = "content_type"
            case customLabel = "custom_label"
        }
    }

    static func flightDocumentSignedURL(path: String) async throws -> URL {
        try await R2Storage.readURL(.flightDocument, path: path)
    }

    static func uploadFlightDocument(coupleID: UUID, parentID: UUID, data: Data, contentType: String, fileExtension: String) async throws -> String {
        let path = "\(coupleID)/\(parentID)/\(UUID().uuidString).\(fileExtension)"
        try await R2Storage.upload(.flightDocument, path: path, data: data, contentType: contentType)
        return path
    }

    @discardableResult
    static func insertFlightDocument(coupleID: UUID, flightID: UUID?, tripID: UUID?, docType: FlightDocumentType, data: Data, contentType: String, fileExtension: String, originalFilename: String?, customLabel: String? = nil) async throws -> FlightDocument {
        guard let userID = currentUserID else { throw BackendError.notAuthenticated }
        let parentID = flightID ?? tripID
        guard let parentID else { throw BackendError.notAuthenticated }
        let path = try await uploadFlightDocument(coupleID: coupleID, parentID: parentID, data: data, contentType: contentType, fileExtension: fileExtension)

        let insert = FlightDocumentInsert(
            flightId: flightID, tripId: tripID, uploadedBy: userID,
            docType: docType.rawValue, filePath: path, originalFilename: originalFilename, contentType: contentType,
            // Only ever set for `.other` — the column has a check constraint saying so, since a
            // boarding pass renamed to something else would be unfindable on a screen where the
            // label is how you tell rows apart.
            customLabel: docType == .other ? customLabel : nil
        )
        // The blob is already in storage by the time the row is attempted, and the row is what
        // `flight_documents_insert_members_active` gates on a subscription (20261028000000). A
        // refusal here would otherwise leave the file behind forever: paid for in storage, reachable
        // by nothing, and invisible to the person who uploaded it. So the upload is undone before
        // the error is rethrown.
        //
        // `removeFlightDocumentObjects` and not a thrown cleanup — a failure to tidy up must not
        // replace the error that explains what actually happened.
        let rows: [FlightDocumentRow]
        do {
            rows = try await supabase
                .from("flight_documents")
                .insert(insert)
                .select()
                .execute()
                .value
        } catch {
            await removeFlightDocumentObjects([path])
            throw error
        }
        guard let row = rows.first else {
            await removeFlightDocumentObjects([path])
            throw BackendError.avatarURLFailed
        }
        let url = try? await flightDocumentSignedURL(path: row.filePath)
        return FlightDocument(id: row.id, flightID: row.flightId, tripID: row.tripId, uploadedBy: row.uploadedBy, docType: row.docType, filePath: row.filePath, originalFilename: row.originalFilename, contentType: row.contentType, customLabel: row.customLabel, createdAt: row.createdAt, url: url)
    }

    static func fetchFlightDocuments(flightID: UUID? = nil, tripID: UUID? = nil) async throws -> [FlightDocument] {
        var query = supabase.from("flight_documents").select()
        if let flightID {
            query = query.eq("flight_id", value: flightID)
        } else if let tripID {
            query = query.eq("trip_id", value: tripID)
        } else {
            return []
        }
        let rows: [FlightDocumentRow] = try await query.order("created_at", ascending: false).execute().value

        var documents: [FlightDocument] = []
        for row in rows {
            let url = try? await flightDocumentSignedURL(path: row.filePath)
            documents.append(FlightDocument(id: row.id, flightID: row.flightId, tripID: row.tripId, uploadedBy: row.uploadedBy, docType: row.docType, filePath: row.filePath, originalFilename: row.originalFilename, contentType: row.contentType, customLabel: row.customLabel, createdAt: row.createdAt, url: url))
        }
        return documents
    }

    /// Takes the storage path as well as the id, the same way `deleteMemoryPhoto` does and for the
    /// same reason: deleting the row leaves the file behind, and a boarding pass is exactly the
    /// kind of thing (full name, PNR, seat, frequent-flyer number) somebody deletes *because* they
    /// want it gone.
    static func deleteFlightDocument(id: UUID, path: String) async throws {
        try await supabase.from("flight_documents").delete().eq("id", value: id).execute()
        await removeFlightDocumentObjects([path])
    }

    /// Just the `file_path` column — deliberately not `fetchFlightDocuments`, which mints a signed
    /// URL per row. Those are round trips spent building links to files that are about to be
    /// deleted.
    static func flightDocumentPaths(flightID: UUID? = nil, tripID: UUID? = nil) async -> [String] {
        struct PathRow: Decodable {
            var filePath: String
            enum CodingKeys: String, CodingKey { case filePath = "file_path" }
        }
        var query = supabase.from("flight_documents").select("file_path")
        if let flightID {
            query = query.eq("flight_id", value: flightID)
        } else if let tripID {
            query = query.eq("trip_id", value: tripID)
        } else {
            return []
        }
        let rows: [PathRow]? = try? await query.execute().value
        return rows?.map(\.filePath) ?? []
    }

    /// Storage objects aren't reachable from a foreign key, so nothing removes them when the row
    /// pointing at them cascades away — the same gap `deleteMemory` closes for `memory-photos`.
    /// Best-effort: a failure here leaves a file behind, which mustn't turn an otherwise-successful
    /// delete into a thrown error the caller reports as "couldn't delete".
    static func removeFlightDocumentObjects(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        await R2Storage.remove(.flightDocument, paths: paths)
    }
}
