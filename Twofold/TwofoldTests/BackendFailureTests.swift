//
//  BackendFailureTests.swift
//  TwofoldTests
//
//  CORE-23. The game RPCs' exception codes are one table, matched on the Postgres message rather
//  than searched for in the error's description, and every failure is read the same way: what it
//  is called, what the screen says, and whether a write may be sent again.
//

import Foundation
import Testing
import Supabase
@testable import Twofold

struct BackendFailureTests {

    private static func raised(_ code: String) -> PostgrestError {
        PostgrestError(code: "P0001", message: code)
    }

    @Test("each exception an RPC raises becomes the error the screen names", arguments: [
        ("word_guess_daily_limit", BackendError.wordGuessDailyLimit, "You've played today's word. A new one arrives tomorrow."),
        ("word_search_requires_premium", .wordSearchRequiresPremium, "Word Search is part of Twofold Premium."),
        ("connect_four_requires_premium", .connectFourRequiresPremium, "Connect 4 is part of Twofold Premium."),
        ("connect_four_needs_partner", .connectFourNeedsPartner, "Connect 4 needs both of you. Invite your partner to play."),
        ("connect_four_not_your_turn", .notYourTurn, "It's not your turn yet."),
        ("connect_four_column_full", .columnFull, "That column is full."),
        ("connect_four_finished", .gameAlreadyFinished, "This game has finished."),
    ])
    func table(code: String, expected: BackendError, message: String) {
        let error = Self.raised(code)
        #expect(BackendFailure.backendError(for: error)?.errorDescription == expected.errorDescription)
        #expect(BackendFailure.message(for: error) == message)
        #expect((BackendFailure.translating(error) as? BackendError)?.errorDescription == message)
    }

    @Test("every code in the table is matched, and none is part of another")
    func tableIsUnambiguous() {
        let codes = Array(BackendFailure.rpcExceptions.keys)
        for code in codes {
            #expect(codes.filter { $0 != code && $0.contains(code) }.isEmpty, "\(code)")
        }
        #expect(codes.count == 7)
    }

    @Test("a code with more text after it is still named")
    func codeWithDetail() {
        let error = PostgrestError(code: "P0001", message: "connect_four_column_full: column 3")
        #expect(BackendFailure.message(for: error) == "That column is full.")
    }

    @Test("an error the table does not know keeps its own text and stays itself")
    func unknownPassesThrough() {
        let error = PostgrestError(code: "P0001", message: "This couple has already been dissolved")
        #expect(BackendFailure.backendError(for: error) == nil)
        #expect(BackendFailure.message(for: error) == error.localizedDescription)
        #expect(BackendFailure.translating(error) is PostgrestError)
    }

    @Test("a code is read from the Postgres message, not from wherever it appears in a description")
    func onlyPostgresMessages() {
        struct Elsewhere: LocalizedError { var errorDescription: String? { "connect_four_finished" } }
        #expect(BackendFailure.backendError(for: Elsewhere()) == nil)
    }

    @Test("a BackendError is already named, and says its own sentence")
    func backendErrorsStand() {
        #expect(BackendFailure.message(for: BackendError.requestFailed(message: "Nope.")) == "Nope.")
        #expect(BackendFailure.message(for: BackendError.requestFailed(message: nil)) == "Something went wrong. Please try again.")
    }

    @Test("refusals and failures worth retrying are told apart", arguments: [
        (PostgrestError(code: "42501", message: "new row violates row-level security policy") as Error, BackendFailure.Kind.refused),
        (BackendService.WriteAffectedNoRows(), .refused),
        (EdgeFunctions.Failure.status(403, message: nil, body: Data()), .refused),
        (R2Storage.StorageError.refused(status: 403), .refused),
        (EdgeFunctions.Failure.status(401, message: nil, body: Data()), .temporary),
        (EdgeFunctions.Failure.status(500, message: "boom", body: Data()), .temporary),
        (EdgeFunctions.Failure.notAuthenticated, .temporary),
        (URLError(.notConnectedToInternet), .temporary),
        (URLError(.timedOut), .temporary),
        (raised("connect_four_finished"), .temporary),
    ])
    func classification(error: Error, kind: BackendFailure.Kind) {
        #expect(BackendFailure.kind(of: error) == kind, "\(error)")
    }
}

extension PendingMemoryDiskTests {
    /// Serialized with the rest of the URLProtocol-registering suites.
    @Suite("Game RPC answers", .serialized)
    @MainActor
    struct GameRPCAnswerTests {

        private func withRPCAnswer<T>(status: Int, body: String, _ run: () async throws -> T) async rethrows -> T {
            ScriptedRPCProtocol.reset(status: status, body: body)
            URLProtocol.registerClass(ScriptedRPCProtocol.self)
            defer { URLProtocol.unregisterClass(ScriptedRPCProtocol.self) }
            return try await run()
        }

        @Test("a daily-limit refusal from the server arrives as the daily limit")
        func dailyLimit() async {
            let body = #"{"code":"P0001","message":"word_guess_daily_limit","details":null,"hint":null}"#
            let error: Error? = await withRPCAnswer(status: 400, body: body) {
                do { _ = try await BackendService.startWordGuessSession(); return nil } catch { return error }
            }
            guard case BackendError.wordGuessDailyLimit? = error else {
                Issue.record("expected the daily limit, got \(String(describing: error))")
                return
            }
        }

        @Test("a move the server refuses because it is not this player's turn says so")
        func notYourTurn() async {
            let body = #"{"code":"P0001","message":"connect_four_not_your_turn","details":null,"hint":null}"#
            let error: Error? = await withRPCAnswer(status: 400, body: body) {
                do { _ = try await BackendService.playConnectFourMove(sessionID: UUID(), column: 3); return nil } catch { return error }
            }
            guard case BackendError.notYourTurn? = error else {
                Issue.record("expected not-your-turn, got \(String(describing: error))")
                return
            }
        }

        @Test("an RPC that answers with no row is a failed request, not a signed-out one")
        func emptyAnswerIsNotSignedOut() async {
            let error: Error? = await withRPCAnswer(status: 200, body: "[]") {
                do { _ = try await BackendService.startConnectFourSession(); return nil } catch { return error }
            }
            // It used to throw `.notAuthenticated`, and the screen told a signed-in person
            // "You need to be signed in."
            guard case BackendError.requestFailed? = error else {
                Issue.record("expected a failed request, got \(String(describing: error))")
                return
            }
            #expect(!BackendService.isPermanentRefusal(error!))
        }

        @Test("a started session decodes from the set of one PostgREST sends")
        func startDecodes() async throws {
            let id = UUID(), puzzle = UUID()
            let body = #"[{"session_id":"\#(id)","puzzle_id":"\#(puzzle)","resumed":true}]"#
            let start = try await withRPCAnswer(status: 200, body: body) {
                try await BackendService.startWordGuessSession()
            }
            #expect(start.sessionID == id && start.puzzleID == puzzle && start.resumed)
        }
    }
}

/// Answers every PostgREST RPC with a scripted status and body. Matches the project's host, so
/// nothing reaches the real backend.
final class ScriptedRPCProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()

    static func reset(status: Int, body: String) {
        lock.withLock {
            Self.status = status
            Self.body = Data(body.utf8)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == SupabaseConfig.projectURL.host && request.url?.path.contains("/rest/v1/rpc/") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.lock.withLock { (Self.status, Self.body) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
