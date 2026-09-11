//
//  RelationshipRecord.swift
//  Twofold
//
//  What is in a couple's record, and in what order — decided once.
//
//  Three things render this now: the timeline screen, the PDF, and the Word (RTF) export. They had
//  better agree, and the only way to be sure is for none of them to decide it. `CoupleDataExporter`
//  built this privately when the PDF was the only consumer; it is here so a second and third reader
//  cannot quietly assemble a different history.
//
//  The grouping is the part worth stating. A trip carries its own flights and memories rather than
//  those also appearing as entries in their own right: a trip with two legs and six photos is one
//  thing that happened, and listing it as nine separate events on the same afternoon is not a
//  record of anything. Only flights and memories with no trip stand alone.
//

import Foundation

enum RelationshipRecord {
    /// Everything the couple has, in the order it happened.
    ///
    /// Deliberately takes plain arrays rather than fetching: the timeline screen already holds
    /// these in `AppModel` and should not re-fetch to draw what it is looking at, while the
    /// exporters fetch by couple id. Same items either way.
    static func timeline(trips: [Trip], memories: [Memory], flights: [Flight]) -> [ExportTimelineItem] {
        let memoriesByTrip = Dictionary(grouping: memories.filter { $0.tripID != nil }, by: { $0.tripID! })
        let flightsByTrip = Dictionary(grouping: flights.filter { $0.tripID != nil }, by: { $0.tripID! })

        var items: [ExportTimelineItem] = trips.map { trip in
            .trip(
                trip,
                description: trip.notes ?? "",
                linkedFlights: (flightsByTrip[trip.id] ?? []).map {
                    .init(flight: $0, includeAttachments: false, attachments: [])
                },
                linkedMemories: (memoriesByTrip[trip.id] ?? []).map {
                    .init(memory: $0, description: $0.note)
                }
            )
        }
        items += memories.filter { $0.tripID == nil }.map { .memory($0, description: $0.note) }
        items += flights.filter { $0.tripID == nil }.map { .flight($0, includeAttachments: false, attachments: []) }

        return items.sorted { $0.date < $1.date }
    }
}
