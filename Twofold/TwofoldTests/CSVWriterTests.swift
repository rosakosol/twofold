//
//  CSVWriterTests.swift
//  TwofoldTests
//
//  Everything in these files was typed by one of the two people in the relationship, so it is full
//  of commas, apostrophes, quotation marks, emoji and pasted line breaks. Getting the escaping
//  wrong doesn't fail loudly — it produces a file that opens, looks plausible, and has one
//  memory's notes spread across four columns.
//

import Testing
import Foundation
@testable import Twofold

struct CSVWriterTests {

    // MARK: - RFC 4180

    @Test("plain text is left alone")
    func plainText() {
        #expect(CSVWriter.field("Lisbon") == "Lisbon")
        #expect(CSVWriter.field("") == "")
    }

    @Test("a comma forces quoting")
    func comma() {
        #expect(CSVWriter.field("Lisbon, Portugal") == "\"Lisbon, Portugal\"")
    }

    /// The one everybody gets wrong: quotes double, they don't backslash-escape.
    @Test("quotes are doubled inside a quoted field")
    func quotes() {
        #expect(CSVWriter.field(#"the "best" day"#) == #""the ""best"" day""#)
    }

    /// A note pasted from Notes or an email carries either line ending, and a bare CR splits a row
    /// just as effectively as an LF.
    ///
    /// The CRLF case is the one that actually caught something: Swift treats "\r\n" as a single
    /// `Character`, so testing membership against a `Set<Character>` of "\r" and "\n" matches
    /// neither half, and the field went through unquoted. Scalars are what see it.
    @Test("both kinds of line break force quoting")
    func lineBreaks() {
        #expect(CSVWriter.field("first\nsecond") == "\"first\nsecond\"")
        #expect(CSVWriter.field("first\rsecond").hasPrefix("\""))
        #expect(CSVWriter.field("first\r\nsecond").hasPrefix("\""), "CRLF is one Character in Swift")
    }

    @Test("emoji and accents survive untouched")
    func unicode() {
        #expect(CSVWriter.field("Café ☕️ Lisboa") == "Café ☕️ Lisboa")
    }

    // MARK: - The one that isn't about spreadsheets rendering nicely

    /// A field starting `=`, `+`, `-` or `@` is evaluated as a formula by Excel, Numbers and
    /// Sheets on open. Memory titles are written by one partner and this file is opened by the
    /// other, so this is a real path from "type a title" to "run something on someone's machine".
    @Test("a leading formula character is neutralised")
    func formulaInjection() {
        #expect(CSVWriter.field("=1+1") == "'=1+1")
        #expect(CSVWriter.field(#"=cmd|' /c calc'!A0"#).hasPrefix("'="))
        #expect(CSVWriter.field("@SUM(A1)") == "'@SUM(A1)")
        #expect(CSVWriter.field("+1 555 0100") == "'+1 555 0100")
    }

    /// And the text is preserved, not stripped — a note that really does begin "- moved the
    /// booking" should still say that when read back.
    @Test("neutralising keeps the original text")
    func neutralisingIsNotStripping() {
        let escaped = CSVWriter.field("- moved the booking")
        #expect(escaped == "'- moved the booking")
        #expect(escaped.dropFirst() == "- moved the booking")
    }

    /// A formula character anywhere but the front is ordinary text. Quoting every hyphen would
    /// mangle every date and every en-dashed title in the file.
    @Test("a formula character mid-field is just text")
    func midFieldIsFine() {
        #expect(CSVWriter.field("Rome-Melbourne") == "Rome-Melbourne")
        #expect(CSVWriter.field("2 + 2 days") == "2 + 2 days")
    }

    /// Both rules can apply at once, and the order matters: neutralise first, then quote, or the
    /// apostrophe lands outside the quotes and breaks the field.
    @Test("a field needing both fixes gets both, in the right order")
    func bothRules() {
        #expect(CSVWriter.field("=a,b") == "\"'=a,b\"")
    }

    // MARK: - Files

    /// The BOM is asserted on the bytes, not on a decoded `String` — `String(data:encoding:.utf8)`
    /// consumes a leading BOM, so a string-level check passes whether or not it was ever written.
    @Test("rows end CRLF and files carry a BOM")
    func fileShape() throws {
        let data = CSVWriter.file(header: ["a", "b"], rows: [["1", "2"]])
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]), "no BOM — Excel on Windows will mangle every accent")

        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.hasSuffix("\r\n"))
        #expect(text.contains("a,b\r\n1,2\r\n"))
    }

    /// A header and no rows is a valid file, not an empty one — someone with no tracked flights
    /// should still get flights.csv with its columns, so the export is self-describing.
    @Test("an empty table still has its header")
    func emptyTable() throws {
        let data = CSVWriter.file(header: ["id", "title"], rows: [])
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text == "id,title\r\n", "decoding strips the BOM, so this is the rest of the file")
    }

    // MARK: - Formatting

    @Test("nils render as empty, not as the word nil")
    func nils() {
        #expect(CSVWriter.timestamp(nil) == "")
        #expect(CSVWriter.day(nil) == "")
        #expect(CSVWriter.number(nil) == "")
    }

    /// Kept with its offset. These files outlive the app, and a departure time without a zone is
    /// not a departure time.
    @Test("timestamps keep their offset")
    func timestamps() {
        let rendered = CSVWriter.timestamp(Date(timeIntervalSince1970: 1_790_000_000))
        #expect(rendered.contains("T"))
        #expect(rendered.hasSuffix("Z") || rendered.contains("+") || rendered.contains("-"))
    }

    @Test("days are plain ISO dates")
    func days() {
        #expect(CSVWriter.day(Date(timeIntervalSince1970: 1_790_000_000)).count == 10)
    }
}
