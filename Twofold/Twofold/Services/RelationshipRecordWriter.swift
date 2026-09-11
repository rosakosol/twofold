//
//  RelationshipRecordWriter.swift
//  Twofold
//
//  The relationship record as an editable document, for someone who wants to keep writing in it.
//
//  ---------------------------------------------------------------------------
//  Why the RTF is written by hand
//  ---------------------------------------------------------------------------
//
//  The obvious implementation is `NSAttributedString.data(from:documentAttributes:)` with
//  `.documentType: .rtf`, building the document with `NSTextAttachment`s for the photos. It
//  produces valid RTF and silently drops every image: a document with a heading and one attachment
//  comes out at 322 bytes containing no `\pict` at all. Attachments survive only into `.rtfd`,
//  which is a *bundle* — a directory, not a file anyone can email — so it is not a way out either.
//
//  RTF has supported embedded pictures for thirty years; it is Apple's iOS writer that will not
//  emit them. So the RTF is generated here. It is a plain-text control-word format, and the whole
//  of what this needs is headings, paragraphs and `\pict` groups of hex-encoded PNG.
//
//  Not .docx, for the same reason as before: a .docx is a zip of OOXML parts with their own
//  relationship graph, no Apple API writes one, and Word is entitled to be strict about it. RTF
//  opens as a first-class editable document in Word, Pages and Google Docs.
//
//  Built from `RelationshipRecord.timeline`, the same items the screen and the PDF use, so the
//  three cannot disagree about what happened or in what order.
//

import Foundation
import UIKit

enum RelationshipRecordWriter {
    /// Writes the record to a temporary `.rtf` and returns it, or nil if there is nothing to write.
    static func rtf(items: [ExportTimelineItem], selfName: String, partnerName: String) async -> URL? {
        guard !items.isEmpty else { return nil }

        var rtf = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Helvetica;}}"#
        rtf += #"\f0\fs24"#

        rtf += paragraph(escape("Our Story"), bold: true, sizeHalfPoints: 56)
        rtf += paragraph(escape("\(selfName) & \(partnerName)"), sizeHalfPoints: 28)
        rtf += #"\par"#

        for item in items {
            rtf += paragraph(escape(title(for: item)), bold: true, sizeHalfPoints: 36)
            rtf += paragraph(escape(item.date.formatted(date: .long, time: .omitted)), sizeHalfPoints: 20)

            let detail = detail(for: item)
            if !detail.isEmpty {
                for line in detail.split(separator: "\n", omittingEmptySubsequences: false) {
                    rtf += paragraph(escape(String(line)), sizeHalfPoints: 24)
                }
            }

            for photo in photos(in: item) {
                if let picture = await picture(for: photo) {
                    rtf += picture + #"\par"#
                }
            }
            rtf += #"\par"#
        }

        rtf += "}"

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Our Story.rtf")
        guard (try? Data(rtf.utf8).write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    // MARK: - RTF pieces

    /// RTF is ASCII with control words, so three characters have to be escaped and anything above
    /// ASCII has to be spelled as `\uN?` — the `?` being the substitute a reader that cannot
    /// handle Unicode shows instead. Without this a partner's name with an accent in it, or the
    /// arrow in a flight route, corrupts everything after it.
    private static func escape(_ text: String) -> String {
        var out = ""
        for character in text.unicodeScalars {
            switch character {
            case "\\": out += #"\\"#
            case "{": out += #"\{"#
            case "}": out += #"\}"#
            case let c where c.value < 128: out.unicodeScalars.append(c)
            default:
                // Signed 16-bit, as the spec requires; anything outside the BMP is written as its
                // surrogate pair, which is what `UTF16View` yields.
                for unit in String(character).utf16 {
                    out += "\\u\(Int16(bitPattern: unit))?"
                }
            }
        }
        return out
    }

    private static func paragraph(_ escaped: String, bold: Bool = false, sizeHalfPoints: Int) -> String {
        let open = bold ? #"\b"# : ""
        let close = bold ? #"\b0"# : ""
        return #"\pard\sa120\fs\#(sizeHalfPoints)\#(open) \#(escaped)\#(close)\par"#
    }

    /// One image as a `\pict` group.
    ///
    /// `picwgoal`/`pichgoal` are the *rendered* size in twips (1/1440 inch, so points × 20) and are
    /// what the reader lays out to; `picw`/`pich` describe the bitmap itself. Getting the goal
    /// values wrong is how an image opens at the size of a postage stamp or of a wall.
    private static func picture(for photo: MemoryPhoto) async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: photo.url),
              let image = UIImage(data: data)
        else { return nil }

        // Scaled before encoding. A dozen full-resolution camera photos hex-encoded — which doubles
        // their size again — produces a file too large to email, which is the main thing anyone
        // does with one of these.
        let maxWidth: CGFloat = 420
        let scale = min(1, maxWidth / max(image.size.width, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let scaled = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = scaled.pngData() else { return nil }

        let widthTwips = Int(size.width * 20)
        let heightTwips = Int(size.height * 20)
        let hex = png.map { String(format: "%02x", $0) }.joined()

        return #"{\pict\pngblip\picw\#(Int(size.width))\pich\#(Int(size.height))"#
            + #"\picwgoal\#(widthTwips)\pichgoal\#(heightTwips) "#
            + hex
            + "}"
    }

    // MARK: - What each entry says

    private static func title(for item: ExportTimelineItem) -> String {
        switch item {
        case .trip(let trip, _, _, _): "\(trip.origin.displayCity) → \(trip.destination.displayCity)"
        case .memory(let memory, _): memory.title.isEmpty ? "A moment" : memory.title
        case .flight(let flight, _, _): flightRoute(flight)
        }
    }

    /// Airports carry an optional city and an optional IATA code, and a flight with neither is
    /// still a flight. Falling through both rather than printing an empty arrow.
    static func flightRoute(_ flight: Flight) -> String {
        let from = flight.origin.city ?? flight.origin.iata ?? "Unknown"
        let to = flight.destination.city ?? flight.destination.iata ?? "Unknown"
        return "\(from) → \(to)"
    }

    private static func detail(for item: ExportTimelineItem) -> String {
        switch item {
        case .trip(_, let description, let flights, let memories):
            var parts: [String] = []
            if !description.isEmpty { parts.append(description) }
            for flight in flights {
                parts.append("Flight \(flight.flight.displayNumber): \(flightRoute(flight.flight))")
            }
            for memory in memories where !memory.description.isEmpty {
                parts.append(memory.description)
            }
            return parts.joined(separator: "\n")
        case .memory(_, let description):
            return description
        case .flight(let flight, _, _):
            return "Flight \(flight.displayNumber)"
        }
    }

    private static func photos(in item: ExportTimelineItem) -> [MemoryPhoto] {
        switch item {
        case .memory(let memory, _): memory.photos
        case .trip(_, _, _, let memories): memories.flatMap { $0.memory.photos }
        case .flight: []
        }
    }
}
