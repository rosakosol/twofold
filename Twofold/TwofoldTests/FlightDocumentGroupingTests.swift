//
//  FlightDocumentGroupingTests.swift
//  TwofoldTests
//
//  How attached documents are labelled and grouped on the flight screen.
//
//  The gap this pins: everything that wasn't a boarding pass or an itinerary rendered as the same
//  generic "Travel documents", so a visa, travel insurance and a hotel confirmation on one flight
//  were three identical-looking rows. Grouping on the *name* rather than on `docType` is what makes
//  them tellable apart, and it's the reason a custom name exists at all.
//

import Testing
import Foundation
@testable import Twofold

struct FlightDocumentGroupingTests {

    private func document(
        _ docType: FlightDocumentType,
        customLabel: String? = nil,
        filename: String? = nil,
        createdAt: Date = .now
    ) -> FlightDocument {
        FlightDocument(
            uploadedBy: UUID(), docType: docType, filePath: "couple/flight/\(UUID()).pdf",
            originalFilename: filename, contentType: "application/pdf",
            customLabel: customLabel, createdAt: createdAt
        )
    }

    // MARK: - What a row is called

    @Test("a custom name wins over the type's generic label")
    func customLabelIsTheDisplayName() {
        #expect(document(.other, customLabel: "Spain visa").displayLabel == "Spain visa")
    }

    @Test("without a custom name, the type's own label is used")
    func typeLabelIsTheFallback() {
        #expect(document(.boardingPass).displayLabel == "Boarding pass")
        #expect(document(.itinerary).displayLabel == "Itinerary")
        #expect(document(.other).displayLabel == "Travel documents")
    }

    /// A label of nothing but spaces would render as a blank heading, which is worse than the
    /// generic one it replaced.
    @Test("a blank custom name falls back rather than rendering an empty heading")
    func whitespaceOnlyLabelFallsBack() {
        #expect(document(.other, customLabel: "   ").displayLabel == "Travel documents")
        #expect(document(.other, customLabel: "").displayLabel == "Travel documents")
    }

    // MARK: - Grouping

    /// The reported case: several custom-named documents must not collapse into one pile.
    @Test("differently-named documents get their own headings")
    func customNamesDoNotCollapseTogether() {
        let groups = FlightDocument.grouped([
            document(.other, customLabel: "Spain visa"),
            document(.other, customLabel: "Travel insurance"),
            document(.other, customLabel: "Hotel booking"),
        ])
        #expect(groups.map(\.label) == ["Spain visa", "Travel insurance", "Hotel booking"])
        #expect(groups.allSatisfy { $0.documents.count == 1 })
    }

    /// The other half: several files under one tag is a supported thing to do, so they belong
    /// under one heading rather than repeating it.
    @Test("several files sharing a tag sit under one heading")
    func sameTagGroupsTogether() {
        let groups = FlightDocument.grouped([
            document(.boardingPass, filename: "outbound.pdf"),
            document(.boardingPass, filename: "return.pdf"),
            document(.itinerary, filename: "trip.pdf"),
        ])
        #expect(groups.count == 2)
        #expect(groups[0].label == "Boarding pass")
        #expect(groups[0].documents.map(\.originalFilename) == ["outbound.pdf", "return.pdf"])
        #expect(groups[1].label == "Itinerary")
    }

    @Test("two documents given the same custom name share a heading")
    func identicalCustomNamesGroupTogether() {
        let groups = FlightDocument.grouped([
            document(.other, customLabel: "Visa", filename: "front.jpg"),
            document(.other, customLabel: "Visa", filename: "back.jpg"),
        ])
        #expect(groups.count == 1)
        #expect(groups[0].documents.count == 2)
    }

    /// Headings follow the order their first document appears in, so the list doesn't reshuffle
    /// itself into some alphabetical order the traveller didn't choose.
    @Test("headings keep the order their first document arrived in")
    func headingOrderFollowsFirstAppearance() {
        let groups = FlightDocument.grouped([
            document(.itinerary),
            document(.boardingPass),
            document(.itinerary),
        ])
        #expect(groups.map(\.label) == ["Itinerary", "Boarding pass"])
        #expect(groups[0].documents.count == 2)
    }

    /// An unnamed `.other` and a named one are genuinely different headings — grouping on the raw
    /// type would have merged them, which is the bug.
    @Test("a named document doesn't fall back into the generic pile")
    func namedAndUnnamedOthersStaySeparate() {
        let groups = FlightDocument.grouped([
            document(.other, customLabel: "Spain visa"),
            document(.other),
        ])
        #expect(groups.map(\.label) == ["Spain visa", "Travel documents"])
    }

    @Test("nothing in, nothing out")
    func emptyInEmptyOut() {
        #expect(FlightDocument.grouped([]).isEmpty)
    }
}
