//
//  BackendFailure.swift
//  Twofold
//
//  One place that reads a failed backend call (CORE-23): which `BackendError` it stands for, the
//  sentence a screen shows for it, and whether it was a refusal or a failure worth retrying.
//
//  The game RPCs refuse with `raise exception '<code>' using errcode = 'P0001'`. Each start and
//  move function used to recognise those by searching the whole error's description for the code,
//  eight strings across five functions. They are one table here, matched on the Postgres message
//  itself.
//

import Foundation
import Supabase

enum BackendFailure {

    /// Exception codes the RPCs raise, and what the app calls them. Each is an ordinary outcome
    /// with something better to say than the raw code: an upgrade, an invite, a board to re-read.
    static let rpcExceptions: [String: BackendError] = [
        "word_guess_daily_limit": .wordGuessDailyLimit,
        "word_search_requires_premium": .wordSearchRequiresPremium,
        "connect_four_requires_premium": .connectFourRequiresPremium,
        "connect_four_needs_partner": .connectFourNeedsPartner,
        "connect_four_not_your_turn": .notYourTurn,
        "connect_four_column_full": .columnFull,
        "connect_four_finished": .gameAlreadyFinished,
        // Raised as sentences, not codes. Matched whole, as the codes are.
        "This difficulty requires Premium": .sudokuDifficultyRequiresPremium,
        "This theme requires Premium": .wordSearchThemeRequiresPremium,
        "This deck requires Premium": .deckRequiresPremium,
    ]

    /// The `BackendError` this failure stands for, or nil when it is not one the app names.
    static func backendError(for error: Error) -> BackendError? {
        switch error {
        case let error as BackendError:
            return error
        case let error as PostgrestError:
            let message = error.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if let known = rpcExceptions[message] { return known }
            // A message with more after the code still names it. No code is part of another, so
            // which one matches does not depend on the table's order.
            return rpcExceptions.first { message.contains($0.key) }?.value
        default:
            return nil
        }
    }

    /// The error to rethrow: the named `BackendError` when there is one, otherwise the original,
    /// so `isPermanentRefusal` and the outbox still see what actually happened.
    static func translating(_ error: Error) -> Error {
        backendError(for: error) ?? error
    }

    /// What a screen says about this failure.
    static func message(for error: Error) -> String {
        backendError(for: error)?.errorDescription ?? error.localizedDescription
    }

    /// Whether this failure is the server saying the couple's plan does not include it, which a
    /// screen answers with the paywall rather than an error.
    static func opensPaywall(_ error: Error) -> Bool {
        switch backendError(for: error) {
        case .connectFourRequiresPremium?, .wordSearchRequiresPremium?, .sudokuDifficultyRequiresPremium?,
             .wordSearchThemeRequiresPremium?, .deckRequiresPremium?:
            true
        default:
            false
        }
    }

    /// Whether a failed write may be kept and sent again later. See
    /// `BackendService.isPermanentRefusal`, which decides it.
    enum Kind: Equatable {
        /// The server said no. Retrying changes nothing, so an optimistic edit is rolled back.
        case refused
        /// The server was not heard, or failed. The outbox sends it again.
        case temporary
    }

    static func kind(of error: Error) -> Kind {
        BackendService.isPermanentRefusal(error) ? .refused : .temporary
    }
}

extension BackendService {
    /// Calls an RPC that `returns table` and answers one row, which PostgREST sends as a set of
    /// one. A refusal comes back translated (see `BackendFailure`).
    static func rpcSingle<Row: Decodable>(_ function: String, params: some Encodable & Sendable) async throws -> Row {
        try await firstRow { try await supabase.rpc(function, params: params).execute().value }
    }

    static func rpcSingle<Row: Decodable>(_ function: String) async throws -> Row {
        try await firstRow { try await supabase.rpc(function).execute().value }
    }

    private static func firstRow<Row>(_ fetch: () async throws -> [Row]) async throws -> Row {
        let rows: [Row]
        do {
            rows = try await fetch()
        } catch {
            throw BackendFailure.translating(error)
        }
        // No row is a server that answered oddly, not a signed-out person. This used to throw
        // `.notAuthenticated`, so the screen said "You need to be signed in" to someone who was.
        guard let row = rows.first else { throw BackendError.requestFailed(message: nil) }
        return row
    }
}
