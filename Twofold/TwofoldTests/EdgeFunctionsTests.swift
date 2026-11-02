//
//  EdgeFunctionsTests.swift
//  TwofoldTests
//
//  CORE-22. Every Edge Function call goes through `EdgeFunctions`: one place for the fresh token,
//  the timeout, the headers and the shape of a failure.
//

import Foundation
import Testing
@testable import Twofold

extension PendingMemoryDiskTests {
    /// Serialized with the rest of the URLProtocol-registering suites.
    @Suite("One Edge Function caller", .serialized)
    @MainActor
    struct EdgeFunctionsTests {

        private struct Active: Decodable, Equatable { var active: Bool }

        /// Runs `body` with `ScriptedEdgeProtocol` answering every function call and the session's
        /// token replaced, putting both back afterwards.
        @discardableResult
        private func withScriptedFunctions<T>(
            status: Int = 200,
            body: String = "{}",
            token: String? = "fresh-token",
            _ run: () async throws -> T
        ) async rethrows -> T {
            ScriptedEdgeProtocol.reset(status: status, body: body)
            URLProtocol.registerClass(ScriptedEdgeProtocol.self)
            let previous = BackendService.validatedAccessToken
            BackendService.validatedAccessToken = { token }
            defer {
                URLProtocol.unregisterClass(ScriptedEdgeProtocol.self)
                BackendService.validatedAccessToken = previous
            }
            return try await run()
        }

        @Test("a call carries the validated session's token")
        func usesFreshToken() async throws {
            try await withScriptedFunctions {
                try await EdgeFunctions.send("sync-my-subscription")
            }
            #expect(ScriptedEdgeProtocol.authorizations == ["Bearer fresh-token"])
        }

        @Test("a token the caller already holds is sent as it is, without asking for another")
        func suppliedTokenWins() async throws {
            try await withScriptedFunctions(token: nil) {
                try await EdgeFunctions.send("storage-url", body: ["paths": []], accessToken: "batch-token")
            }
            #expect(ScriptedEdgeProtocol.authorizations == ["Bearer batch-token"])
        }

        @Test("with no session nothing is sent, and the caller is told why")
        func noSessionSendsNothing() async {
            await withScriptedFunctions(token: nil) {
                await #expect(throws: EdgeFunctions.Failure.notAuthenticated) {
                    try await EdgeFunctions.send("delete-account")
                }
            }
            #expect(ScriptedEdgeProtocol.authorizations.isEmpty)
        }

        @Test("a 2xx answer is decoded as the type asked for")
        func decodesSuccess() async throws {
            let row: Active = try await withScriptedFunctions(body: #"{"active":true}"#) {
                try await EdgeFunctions.invoke("sync-my-subscription")
            }
            #expect(row == Active(active: true))
        }

        @Test("a 2xx answer of the wrong shape is undecodable, not a crash or a default")
        func undecodableSuccess() async {
            await withScriptedFunctions(body: #"{"something":"else"}"#) {
                await #expect(throws: EdgeFunctions.Failure.undecodable) {
                    let _: Active = try await EdgeFunctions.invoke("sync-my-subscription")
                }
            }
        }

        @Test("a refusal keeps its status and the function's own explanation")
        func failureCarriesMessage() async {
            let body = #"{"error":"You've done this 10 times this hour."}"#
            await withScriptedFunctions(status: 429, body: body) {
                await #expect(throws: EdgeFunctions.Failure.status(429, message: "You've done this 10 times this hour.", body: Data(body.utf8))) {
                    try await EdgeFunctions.send("parse-flight-email", body: ["subject": "x"])
                }
            }
        }

        @Test("a failure with no explanation has no message, so the caller's own wording shows")
        func failureWithoutMessage() async {
            await withScriptedFunctions(status: 500, body: #"{"error":""}"#) {
                await #expect(throws: EdgeFunctions.Failure.status(500, message: nil, body: Data(#"{"error":""}"#.utf8))) {
                    try await EdgeFunctions.send("submit-help-message")
                }
            }
        }

        @Test("a refused storage request reaches R2Storage as a refusal, so the write is not retried for ever")
        func storageRefusal() async {
            let error: Error? = await withScriptedFunctions(status: 403) {
                do {
                    _ = try await R2Storage.readURL(.avatar, path: "tests/\(UUID().uuidString).jpg")
                    return nil
                } catch {
                    return error
                }
            }
            guard case R2Storage.StorageError.refused(403)? = error else {
                Issue.record("expected a refusal, got \(String(describing: error))")
                return
            }
            #expect(BackendService.isPermanentRefusal(error!))
        }

        @Test("the request names the function, posts JSON with the key and bearer, and has a timeout")
        func requestShape() throws {
            let body = Data(#"{"a":1}"#.utf8)
            let request = EdgeFunctions.request("notify-couple-event", body: body, accessToken: "t")
            #expect(request.url == SupabaseConfig.projectURL.appendingPathComponent("functions/v1/notify-couple-event"))
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
            #expect(request.value(forHTTPHeaderField: "apiKey") == SupabaseConfig.publishableKey)
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.httpBody == body)
            #expect(request.timeoutInterval == EdgeFunctions.defaultTimeout)
            #expect(EdgeFunctions.request("resolve-flight", body: nil, accessToken: "t", timeout: EdgeFunctions.slowTimeout).timeoutInterval == 60)
        }
    }
}

/// Answers every Edge Function request with a scripted status and body, recording each request's
/// Authorization header. Matches the project's host, so nothing reaches the real backend.
final class ScriptedEdgeProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [String] = []
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()

    static var authorizations: [String] { lock.withLock { recorded } }
    static func reset(status: Int, body: String) {
        lock.withLock {
            recorded = []
            Self.status = status
            Self.body = Data(body.utf8)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SupabaseConfig.projectURL.host && request.url?.path.contains("/functions/v1/") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        let (status, body) = Self.lock.withLock {
            Self.recorded.append(header)
            return (Self.status, Self.body)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
