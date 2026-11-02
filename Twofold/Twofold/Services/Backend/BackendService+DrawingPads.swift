//
//  BackendService+DrawingPads.swift
//  Twofold
//
//  Each partner's drawing pad image.
//

import Foundation
import Supabase

extension BackendService {

    // MARK: - Drawing pads

    /// Each person's home-screen drawing lives at one fixed path, so a re-save overwrites
    /// rather than accumulates — no separate DB row needed, the path is fully deterministic.
    private static func drawingPadPath(coupleID: UUID, personID: UUID) -> String {
        "\(coupleID)/\(personID)/pad.png"
    }

    /// `drawing-pads` is a private bucket (see `avatarSignedURL`'s doc comment — same fix,
    /// same reasoning). A signed URL is what both the in-app pad views and
    /// `WidgetSnapshotWriter` use directly; the widget extension itself has no Supabase session
    /// to sign anything with, so it can no longer fetch this bucket live on its own — see
    /// `WidgetSnapshot.mySignedDrawingPadURL`/`partnerSignedDrawingPadURL`, refreshed by the main
    /// app and simply read (and fetched, still over a real network call) by the widget from
    /// there. See `drawingPadURLLifetimeSeconds` for how long one lasts and why.
    static func drawingPadSignedURL(coupleID: UUID, personID: UUID) async throws -> URL {
        // The twelve hours now live server-side, in `storage-url`'s own table of expiries —
        // `drawingPadURLLifetimeSeconds` stays as the client-side statement of the same number and
        // the place the reasoning is written down.
        try await R2Storage.readURL(.drawingPad, path: drawingPadPath(coupleID: coupleID, personID: personID))
    }

    /// How long a drawing-pad signed URL stays valid.
    ///
    /// Twelve hours, down from forty-eight. This is the only signed URL the app writes to disk:
    /// `WidgetSnapshot` persists it into the app-group defaults, because the widget extension has
    /// no Supabase session and cannot sign anything itself. Everything else is minted per load and
    /// never stored, so this is the one worth keeping short — a signature is a bearer credential,
    /// and this one sits in a plist.
    ///
    /// Not shorter than twelve, because the widget's liveness depends on it. The pad path is
    /// stable and overwritten in place, so an unexpired URL keeps resolving to whatever the
    /// current drawing is — which is how a partner's new doodle reaches a home screen on the
    /// widget's own 30-minute timeline, with neither main app having to run. Twelve still covers a
    /// normal day between app opens, and `WidgetSnapshotWriter` re-signs on every refresh, so in
    /// practice the window is shorter again. If one does lapse, the widget's fetch fails and it
    /// falls back to its last-good cached image, the same as any other network failure it already
    /// handles.
    ///
    /// A named constant rather than a literal because three doc comments across two targets quote
    /// this number, and the previous one had already been written down in all three.
    static let drawingPadURLLifetimeSeconds = 60 * 60 * 12

    /// Uploads the signed-in user's drawing pad and returns a signed URL for immediate local
    /// display — no separate cache-busting needed, same reasoning as `uploadAvatar`.
    @discardableResult
    static func uploadDrawingPad(coupleID: UUID, personID: UUID, imageData: Data) async throws -> URL {
        let path = drawingPadPath(coupleID: coupleID, personID: personID)
        try await R2Storage.upload(.drawingPad, path: path, data: imageData, contentType: "image/png")
        guard let url = try? await drawingPadSignedURL(coupleID: coupleID, personID: personID) else {
            throw BackendError.avatarURLFailed
        }
        return url
    }
}
