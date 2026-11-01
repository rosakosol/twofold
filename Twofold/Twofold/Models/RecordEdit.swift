//
//  RecordEdit.swift
//  Twofold
//
//  One person's edit to a trip or a memory: the fields they changed, and nothing else (HOME-7).
//
//  An edit used to send the whole row from the editor's copy. Both partners can edit the same
//  trip or memory, so whatever that copy said about the fields nobody touched went to the server
//  too, and a partner's change to one field was silently undone by an edit to another — with
//  nothing on either screen to say so. Built by comparing the edited copy with the one the editor
//  started from, so a field the person left alone stays out of it even when the screen's copy of
//  it is out of date (HOME-5).
//
//  Two people changing the *same* field is still last-writer-wins, which is the honest answer
//  for a title or a date.
//

import Foundation

/// A field whose new value may itself be nil — a place removed, notes cleared. The wrapper keeps
/// "changed to nothing" apart from "not changed", which a bare optional cannot say.
struct Changed<Value: Codable & Hashable>: Codable, Hashable {
    var value: Value
}

struct MemoryEdit: Codable, Hashable {
    let memoryID: UUID
    var title: String?
    var place: Changed<Place?>?
    var date: Date?
    var note: String?

    init(memoryID: UUID, title: String? = nil, place: Changed<Place?>? = nil, date: Date? = nil, note: String? = nil) {
        self.memoryID = memoryID
        self.title = title
        self.place = place
        self.date = date
        self.note = note
    }

    /// What changed between the copy the editor started from and the one it saved.
    init(from base: Memory, to edited: Memory) {
        self.init(memoryID: edited.id)
        if edited.title != base.title { title = edited.title }
        if edited.place != base.place { place = Changed(value: edited.place) }
        if edited.date != base.date { date = edited.date }
        if edited.note != base.note { note = edited.note }
    }

    /// Every field — what an older build queued (`PendingWrite.memory`), sent as it always was.
    init(allFieldsOf memory: Memory) {
        self.init(memoryID: memory.id, title: memory.title, place: Changed(value: memory.place), date: memory.date, note: memory.note)
    }

    var isEmpty: Bool { title == nil && place == nil && date == nil && note == nil }

    func apply(to memory: inout Memory) {
        if let title { memory.title = title }
        if let place { memory.place = place.value }
        if let date { memory.date = date }
        if let note { memory.note = note }
    }

    /// This edit, made after `older` and not yet sent with it: the fields of both, this one's
    /// winning where they overlap. Replacing the older one outright would drop its fields.
    func merged(onto older: MemoryEdit) -> MemoryEdit {
        MemoryEdit(
            memoryID: memoryID,
            title: title ?? older.title,
            place: place ?? older.place,
            date: date ?? older.date,
            note: note ?? older.note
        )
    }
}

struct TripEdit: Codable, Hashable {
    let tripID: UUID
    var travelerIDs: [UUID]?
    var origin: Place?
    var destination: Place?
    var departureDate: Date?
    var arrivalDate: Date?
    var category: TripCategory?
    var notes: Changed<String?>?
    /// Set whenever either city is, from the trip as it is once the edit is applied.
    var distanceKm: Double?

    init(
        tripID: UUID,
        travelerIDs: [UUID]? = nil,
        origin: Place? = nil,
        destination: Place? = nil,
        departureDate: Date? = nil,
        arrivalDate: Date? = nil,
        category: TripCategory? = nil,
        notes: Changed<String?>? = nil,
        distanceKm: Double? = nil
    ) {
        self.tripID = tripID
        self.travelerIDs = travelerIDs
        self.origin = origin
        self.destination = destination
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.category = category
        self.notes = notes
        self.distanceKm = distanceKm
    }

    /// What changed between the copy the editor started from and the one it saved. Flights are
    /// not part of a trip edit.
    init(from base: Trip, to edited: Trip) {
        self.init(tripID: edited.id)
        if edited.travelerIDs != base.travelerIDs { travelerIDs = edited.travelerIDs }
        if edited.origin != base.origin { origin = edited.origin }
        if edited.destination != base.destination { destination = edited.destination }
        if edited.departureDate != base.departureDate { departureDate = edited.departureDate }
        if edited.arrivalDate != base.arrivalDate { arrivalDate = edited.arrivalDate }
        if edited.category != base.category { category = edited.category }
        if edited.notes != base.notes { notes = Changed(value: edited.notes) }
        if edited.distanceKm != base.distanceKm { distanceKm = edited.distanceKm }
    }

    /// Every field — what an older build queued (`PendingWrite.trip`), sent as it always was.
    init(allFieldsOf trip: Trip) {
        self.init(
            tripID: trip.id,
            travelerIDs: trip.travelerIDs,
            origin: trip.origin,
            destination: trip.destination,
            departureDate: trip.departureDate,
            arrivalDate: trip.arrivalDate,
            category: trip.category,
            notes: Changed(value: trip.notes),
            distanceKm: trip.distanceKm
        )
    }

    var isEmpty: Bool {
        travelerIDs == nil && origin == nil && destination == nil && departureDate == nil
            && arrivalDate == nil && category == nil && notes == nil && distanceKm == nil
    }

    func apply(to trip: inout Trip) {
        if let travelerIDs { trip.travelerIDs = travelerIDs }
        if let origin { trip.origin = origin }
        if let destination { trip.destination = destination }
        if let departureDate { trip.departureDate = departureDate }
        if let arrivalDate { trip.arrivalDate = arrivalDate }
        if let category { trip.category = category }
        if let notes { trip.notes = notes.value }
        if let distanceKm { trip.distanceKm = distanceKm }
    }

    /// See `MemoryEdit.merged(onto:)`.
    func merged(onto older: TripEdit) -> TripEdit {
        TripEdit(
            tripID: tripID,
            travelerIDs: travelerIDs ?? older.travelerIDs,
            origin: origin ?? older.origin,
            destination: destination ?? older.destination,
            departureDate: departureDate ?? older.departureDate,
            arrivalDate: arrivalDate ?? older.arrivalDate,
            category: category ?? older.category,
            notes: notes ?? older.notes,
            distanceKm: distanceKm ?? older.distanceKm
        )
    }
}
