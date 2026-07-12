//
//  PublicStorageURL.swift
//  Twofold
//
//  Just the URL-building constants for Supabase's public Storage REST convention — not the
//  full Supabase SDK, which would pull unnecessary auth/networking dependencies into the
//  widget extension for what's just a public, unauthenticated GET. Mirrors
//  BackendService.drawingPadPublicURL's path shape exactly; keep both in sync if the storage
//  layout ever changes.
//
//  Shared with LiveActivitiesExtension (see the "Twofold" folder's membership exception for
//  that target in project.pbxproj).
//

import Foundation

enum PublicStorageURL {
    private static let projectURL = "https://ipfzswswwukfqphloojo.supabase.co"

    static func drawingPad(coupleID: UUID, personID: UUID) -> URL? {
        URL(string: "\(projectURL)/storage/v1/object/public/drawing-pads/\(coupleID)/\(personID)/pad.png")
    }
}
