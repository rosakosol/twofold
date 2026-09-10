//
//  CSVWriter.swift
//  Twofold
//
//  Turning rows of strings into a CSV file, correctly.
//
//  Everything exported here is written by the people in the relationship — memory titles, trip
//  notes, place names — so it contains commas, apostrophes, quotation marks, emoji and line breaks
//  as a matter of course. A naive `joined(separator: ",")` produces a file that opens misaligned in
//  the first spreadsheet anyone tries, with a memory's notes spread across four columns.
//
//  Two rules do the work, both from RFC 4180: a field containing a comma, a quote or a line break
//  is wrapped in quotes, and quotes inside a quoted field are doubled. The third rule below is not
//  from RFC 4180 and matters more.
//

import Foundation

enum CSVWriter {

    /// Scalars that force a field to be quoted. `\r` as well as `\n`, because a note pasted from
    /// another app can carry either, and a bare CR splits a row just as effectively.
    ///
    /// Compared as unicode scalars, not as `Character`s, and that is not a stylistic choice: Swift
    /// treats CRLF as a *single* `Character` — one grapheme cluster — so a `Set<Character>` holding
    /// "\r" and "\n" separately matches neither half of it. A note pasted from a Windows machine
    /// went through unquoted and split the row in two. Scalars see the two codepoints.
    private static let mustQuote: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]

    /// Excel, Numbers and Sheets treat a cell beginning with one of these as a formula and will
    /// evaluate it on open. A memory titled `=cmd|' /c calc'!A0` is a real attack against whoever
    /// opens the export, and the content here is typed by one partner and exported by the other.
    ///
    /// Prefixed with a single quote rather than stripped: the character is part of what someone
    /// wrote — a note starting "-- moved the booking" should still say that — and a leading
    /// apostrophe is the conventional way to tell a spreadsheet "this is text".
    private static let formulaTriggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]

    /// One field, escaped.
    static func field(_ value: String) -> String {
        var value = value

        if let first = value.unicodeScalars.first, formulaTriggers.contains(first) {
            value = "'" + value
        }

        guard value.unicodeScalars.contains(where: { mustQuote.contains($0) }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// One row, terminated. CRLF because RFC 4180 says so and because Excel on Windows is the
    /// least forgiving reader of the three.
    static func row(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",") + "\r\n"
    }

    /// A whole file: header row then body rows.
    ///
    /// Prefixed with a UTF-8 BOM. Without it Excel on Windows reads the file as the system legacy
    /// encoding, and every accented place name and every emoji in a memory title arrives as
    /// mojibake — which for this export is most of the point of it.
    static func file(header: [String], rows: [[String]]) -> Data {
        var text = "\u{FEFF}"
        text += row(header)
        for line in rows {
            text += row(line)
        }
        return Data(text.utf8)
    }

    // MARK: - Formatting helpers

    /// ISO 8601 with the offset kept. A trip's dates mean nothing without knowing where the clock
    /// was, and these files outlive the app that made them.
    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.ISO8601Format(.iso8601)
    }

    /// Date only, for anything whose time of day is not real information (an anniversary, a
    /// memory's day).
    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        return date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    static func number(_ value: Double?, decimals: Int = 2) -> String {
        guard let value else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    static func flag(_ value: Bool) -> String { value ? "yes" : "no" }
}
