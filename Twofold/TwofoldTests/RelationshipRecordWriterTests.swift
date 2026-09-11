//
//  RelationshipRecordWriterTests.swift
//  TwofoldTests
//
//  The Word export is hand-written RTF, and the reason is the first thing worth pinning here.
//
//  `NSAttributedString`'s own RTF writer produces a valid file and silently drops every image: a
//  heading plus one `NSTextAttachment` comes out at ~300 bytes containing no `\pict` at all. That
//  is not a visible failure — the document opens, it is simply missing the photographs, which are
//  the reason anyone wants this file. So the RTF is generated directly, and these tests exist
//  because hand-written RTF has failure modes an attributed string never had: an unescaped brace
//  corrupts everything after it, and a mis-scaled `picwgoal` opens the image the size of a wall.
//

import Testing
import SwiftUI
import Foundation
@testable import Twofold

@MainActor
struct RelationshipRecordWriterTests {

    /// The premise. If Apple's writer ever starts embedding attachments, this test fails and the
    /// hand-written implementation can go.
    @Test("Apple's own RTF writer drops images — which is why this file exists")
    func appleWriterDropsImages() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        let doc = NSMutableAttributedString(string: "Our Story\n")
        doc.append(NSAttributedString(attachment: attachment))

        let data = try #require(try? doc.data(
            from: NSRange(location: 0, length: doc.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("{\\rtf"))
        #expect(!text.contains("\\pict"), "Apple now embeds images — the hand-written writer can go")
    }

    /// Every character RTF reserves, plus one outside ASCII. An unescaped brace does not corrupt
    /// the word it is in — it silently swallows the rest of the document.
    @Test("reserved characters and non-ASCII are escaped")
    func escaping() async throws {
        let memory = Memory(
            id: UUID(),
            title: #"Zoë's {braces} and \backslash"#,
            place: nil,
            date: Date(timeIntervalSince1970: 1_600_000_000),
            note: "Café — naïve",
            photoSeed: 1,
            photos: [],
            tripID: nil
        )
        let url = try #require(await RelationshipRecordWriter.rtf(
            items: [.memory(memory, description: memory.note)],
            selfName: "Rosa", partnerName: "Dara"
        ))
        let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)

        #expect(text.contains(#"\{braces\}"#), "braces not escaped")
        #expect(text.contains(#"\\backslash"#), "backslash not escaped")
        // ë is U+00EB = 235, é is 233, — is U+2014 = 8212.
        #expect(text.contains(#"\u235?"#), "non-ASCII not spelled as \\uN")
        #expect(text.contains("\\u8212?"), "em dash not spelled as \\uN")
        // The raw characters must not survive: an ansi RTF carrying raw UTF-8 is what renders as
        // mojibake in Word.
        #expect(!text.contains("ë"), "raw non-ASCII left in an ansi document")
    }

    /// The document has to parse as RTF, not merely look like it. `NSAttributedString` reading it
    /// back is a real parser's verdict rather than a substring check of my own output.
    @Test("what comes out parses back as RTF, with the text intact")
    func roundTrips() async throws {
        let memory = Memory(
            id: UUID(), title: "Dinner in Singapore", place: nil,
            date: Date(timeIntervalSince1970: 1_600_000_000),
            note: "The one with the chilli crab.", photoSeed: 1, photos: [], tripID: nil
        )
        let url = try #require(await RelationshipRecordWriter.rtf(
            items: [.memory(memory, description: memory.note)],
            selfName: "Rosa", partnerName: "Dara"
        ))

        let restored = try #require(try? NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ))
        let plain = restored.string
        #expect(plain.contains("Our Story"))
        #expect(plain.contains("Rosa & Dara"))
        #expect(plain.contains("Dinner in Singapore"))
        #expect(plain.contains("The one with the chilli crab."))
    }

    @Test("an empty history writes nothing rather than an empty document")
    func emptyIsNil() async {
        let url = await RelationshipRecordWriter.rtf(items: [], selfName: "Rosa", partnerName: "Dara")
        #expect(url == nil)
    }

    /// An airport can arrive with no city and no code at all, and a flight is still a flight.
    @Test("a route with nothing to name it still reads as a route")
    func routeFallsBack() {
        var flight = MockData.activeFlight
        flight.origin.city = nil
        flight.origin.iata = "SIN"
        flight.destination.city = nil
        flight.destination.iata = nil
        #expect(RelationshipRecordWriter.flightRoute(flight) == "SIN → Unknown")
    }
}
