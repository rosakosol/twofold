//
//  FreshAccessTokenTests.swift
//  TwofoldTests
//
//  CORE-7. Edge Function calls sent whatever access token was on disk, expired or not.
//  `currentSession` does not refresh; only `auth.session` does.
//

import Foundation
import Testing
@testable import Twofold

extension PendingMemoryDiskTests {
    /// Serialized with the rest of the URLProtocol-registering suites.
    @Suite("Edge Function calls carry a fresh token", .serialized)
    @MainActor
    struct FreshAccessTokenTests {

        @Test("a storage URL is signed with the validated session's token, not the cached one")
        func storageSigningUsesFreshToken() async {
            CapturingEdgeProtocol.reset()
            URLProtocol.registerClass(CapturingEdgeProtocol.self)
            let previous = BackendService.validatedAccessToken
            BackendService.validatedAccessToken = { "fresh-token" }
            defer {
                URLProtocol.unregisterClass(CapturingEdgeProtocol.self)
                BackendService.validatedAccessToken = previous
            }

            _ = try? await R2Storage.readURL(.avatar, path: "tests/\(UUID().uuidString).jpg")

            #expect(CapturingEdgeProtocol.authorizations == ["Bearer fresh-token"], "the call went out with the cached token, or not at all")
        }
    }
}

/// Answers every Edge Function request with an empty success, recording its Authorization header.
/// Matches the project's host so nothing reaches the real backend from a unit test.
final class CapturingEdgeProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []

    static var authorizations: [String] { lock.withLock { recorded } }
    static func reset() { lock.withLock { recorded = [] } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SupabaseConfig.projectURL.host && request.url?.path.contains("/functions/v1/") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        Self.lock.withLock { Self.recorded.append(header) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"urls":{}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
