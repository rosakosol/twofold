//
//  CoupleDataExporterTests.swift
//  TwofoldTests
//
//  The two places in the export where somebody's typed words become filenames.
//
//  A partner's name and a memory's title can contain anything — slashes, colons, emoji, nothing at
//  all — and a filesystem accepts far less than that. Getting it wrong here doesn't throw: it
//  produces a zip with a broken folder name, or two photos that overwrite each other, on the one
//  copy someone made before a deadline.
//

import Testing
import Foundation
@testable import Twofold

struct CoupleDataExporterTests {

    // MARK: - Photo file names

    /// Indexed by position, not named after the memory. Titles are empty, duplicated and full of
    /// punctuation; indices are none of those, and they are what `memories.csv` prints, so the CSV
    /// and the folder always agree.
    @Test("photo names are indexed, padded and unique")
    func photoNames() {
        let url = URL(string: "https://example.com/a.jpg")!
        #expect(CoupleDataExporter.photoFileName(memoryIndex: 0, photoIndex: 0, url: url) == "memory-0001-01.jpg")
        #expect(CoupleDataExporter.photoFileName(memoryIndex: 11, photoIndex: 2, url: url) == "memory-0012-03.jpg")
    }

    /// Padded so a plain alphabetical sort in Finder matches the order the memories are in. Without
    /// it, memory 10 sorts before memory 2.
    @Test("names sort in the order the memories are in")
    func namesSortNaturally() {
        let url = URL(string: "https://example.com/a.jpg")!
        let names = (0..<12).map { CoupleDataExporter.photoFileName(memoryIndex: $0, photoIndex: 0, url: url) }
        #expect(names == names.sorted(), "padding is what keeps memory 10 after memory 2")
    }

    /// Two photos in one memory must never collide — that would silently lose one of them.
    @Test("photos within a memory get distinct names")
    func photosWithinAMemoryAreDistinct() {
        let url = URL(string: "https://example.com/a.jpg")!
        let names = (0..<5).map { CoupleDataExporter.photoFileName(memoryIndex: 3, photoIndex: $0, url: url) }
        #expect(Set(names).count == 5)
    }

    /// The extension comes from the stored file, lowercased, and falls back rather than producing
    /// a file with no extension that nothing will open by double-clicking.
    @Test("the extension is kept, lowercased, with a fallback")
    func extensions() {
        #expect(CoupleDataExporter.photoFileName(memoryIndex: 0, photoIndex: 0,
                url: URL(string: "https://example.com/a.HEIC")!).hasSuffix(".heic"))
        #expect(CoupleDataExporter.photoFileName(memoryIndex: 0, photoIndex: 0,
                url: URL(string: "https://example.com/photo")!).hasSuffix(".jpg"))
    }

    // MARK: - Folder names

    @Test("an ordinary name becomes an ordinary folder")
    func ordinaryFolderName() {
        #expect(CoupleDataExporter.folderName(for: "Alex") == "alex-twofold-export")
        #expect(CoupleDataExporter.folderName(for: "Mary Anne") == "mary-anne-twofold-export")
    }

    /// The characters that actually break things. A slash would make a nested directory; a colon
    /// is still meaningful to the Finder.
    @Test("path characters are stripped, not preserved")
    func pathCharacters() {
        let name = CoupleDataExporter.folderName(for: "Alex/Sam")
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
    }

    /// A name that is entirely emoji, or entirely punctuation, leaves nothing behind — and a zip
    /// called "-twofold-export" or "" is worse than a generic one.
    @Test("a name that survives nothing still yields a usable folder")
    func emptyAfterCleaning() {
        #expect(CoupleDataExporter.folderName(for: "🙂🙂") == "twofold-twofold-export")
        #expect(CoupleDataExporter.folderName(for: "") == "twofold-twofold-export")
        #expect(CoupleDataExporter.folderName(for: "///") == "twofold-twofold-export")
    }

    /// Never a leading or trailing hyphen, and never a space — both of which make a file awkward
    /// to handle in a terminal and ugly in a share sheet.
    @Test("no stray spaces or hyphens at the edges")
    func edges() {
        let name = CoupleDataExporter.folderName(for: "  Alex  ")
        #expect(!name.hasPrefix("-"))
        #expect(!name.contains(" "))
        #expect(name == "alex-twofold-export")
    }
}
