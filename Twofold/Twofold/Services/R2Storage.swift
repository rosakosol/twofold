//
//  R2Storage.swift
//  Twofold
//
//  Objects live in Cloudflare R2, and this is how the app reaches them.
//
//  Supabase Storage authorised every read itself, out of RLS policies on `storage.objects`, so the
//  client could ask for a signed URL and trust that a "no" came back when it should. R2 authorises
//  nothing: it honours a signature and asks no further questions. So the decision moved server-side
//  to `can_access_storage_object` (migration 20261030000000), and every URL is minted by the
//  `storage-url` Edge Function after that decision goes the caller's way.
//
//  What that means here: this file cannot grant itself anything. It asks, and it gets a URL or a
//  403. There is deliberately no path through it that reaches R2 directly — the credentials that
//  could do that are server-side secrets and never ship in the app.
//
//  Paths are unchanged from the Supabase Storage era. `memory_photos.photo_path` still holds
//  `{coupleID}/{memoryID}/{uuid}.jpg`; the bucket name becomes the leading segment of the R2 key,
//  and `storage-url` adds it. That is why the migration was a copy of bytes and not a rewrite of
//  every row (see `scripts/copy-storage-to-r2.ts`).
//

import Foundation

enum R2Storage {

    /// The four kinds the server knows about. Raw values are the wire contract with `storage-url`,
    /// which maps each to a bucket prefix and to an expiry.
    enum Kind: String {
        case avatar
        case drawingPad = "drawing-pad"
        case memoryPhoto = "memory-photo"
        case flightDocument = "flight-document"
    }

    enum StorageError: Error {
        /// The server declined, or could not be reached. Deliberately one case: a caller cannot do
        /// anything different about a 403 than about a 500, and the two are not distinguishable to
        /// the person holding the phone either — the photo does not appear.
        case urlUnavailable
        case uploadFailed
    }

    // MARK: - Reading

    /// A URL for one object, or a throw.
    static func readURL(_ kind: Kind, path: String) async throws -> URL {
        guard let url = try await signed(kind, op: "read", paths: [path])[path] else {
            throw StorageError.urlUnavailable
        }
        return url
    }

    /// URLs for many objects in one request, keyed by path.
    ///
    /// One round trip rather than one per object, for the reason the batch signing it replaces
    /// already documented: a couple with 200 memories averaging three photos is 600 requests, and
    /// nothing can be drawn until the slowest returns.
    ///
    /// Returns what it got. An empty result is a failure the caller sees as photos with no URL,
    /// which is what a failed sign has always looked like here.
    static func readURLs(_ kind: Kind, paths: [String]) async -> [String: URL] {
        let unique = Array(Set(paths))
        guard !unique.isEmpty else { return [:] }

        // Chunked, because `storage-url` refuses more than `maxPathsPerRequest` in one go and a
        // real library is bigger than that: the caller's own doc comment describes 200 memories
        // averaging three photos. Sending all 600 would earn one 400 and no URLs at all, and the
        // per-path fallback would then make 600 requests — the exact thing batching exists to
        // avoid. Chunks run concurrently, so this is ceil(n/100) round trips rather than n.
        let chunks = stride(from: 0, to: unique.count, by: maxPathsPerRequest).map {
            Array(unique[$0 ..< min($0 + maxPathsPerRequest, unique.count)])
        }

        return await withTaskGroup(of: [String: URL].self) { group in
            for chunk in chunks {
                group.addTask { (try? await signed(kind, op: "read", paths: chunk)) ?? [:] }
            }
            var all: [String: URL] = [:]
            for await chunk in group { all.merge(chunk) { current, _ in current } }
            return all
        }
    }

    /// Mirrors `MAX_PATHS` in the `storage-url` function. A mismatch here is not a crash, it is a
    /// 400 for every oversized batch and a silent collapse back to one request per object.
    private static let maxPathsPerRequest = 100

    // MARK: - Writing

    /// Uploads bytes, by asking for a presigned PUT and then sending them straight to R2.
    ///
    /// Two round trips rather than one, and worth it: the bytes never pass through an Edge
    /// Function, so a large photo costs Supabase nothing and is limited only by R2. The content
    /// type is signed into the URL, so R2 refuses an upload that does not match what was
    /// authorised.
    static func upload(_ kind: Kind, path: String, data: Data, contentType: String) async throws {
        guard let url = try await signed(kind, op: "write", paths: [path], contentType: contentType)[path] else {
            throw StorageError.urlUnavailable
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw StorageError.uploadFailed
        }
    }

    /// Best-effort removal, matching how the Storage `remove` calls this replaces were used —
    /// every caller wrapped them in `try?`, because the database row is the thing that matters and
    /// an orphaned object is tidiness rather than correctness.
    static func remove(_ kind: Kind, paths: [String]) async {
        guard !paths.isEmpty, let urls = try? await signed(kind, op: "delete", paths: paths) else { return }
        await withTaskGroup(of: Void.self) { group in
            for url in urls.values {
                group.addTask {
                    var request = URLRequest(url: url)
                    request.httpMethod = "DELETE"
                    _ = try? await URLSession.shared.data(for: request)
                }
            }
        }
    }

    // MARK: - The one request

    private struct Response: Decodable { let urls: [String: URL] }

    /// Asks `storage-url` for presigned URLs.
    ///
    /// All or nothing by design on the server side: if any path in the batch is refused, none come
    /// back. Partial success would render some photos and silently drop others, which reads as a
    /// network problem rather than a permissions one.
    private static func signed(
        _ kind: Kind,
        op: String,
        paths: [String],
        contentType: String? = nil
    ) async throws -> [String: URL] {
        guard let accessToken = BackendService.currentAccessToken else {
            throw StorageError.urlUnavailable
        }

        var body: [String: Any] = ["kind": kind.rawValue, "op": op, "paths": paths]
        if let contentType { body["contentType"] = contentType }

        var request = URLRequest(url: SupabaseConfig.projectURL.appendingPathComponent("functions/v1/storage-url"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apiKey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw StorageError.urlUnavailable
        }
        return decoded.urls
    }
}
