//
//  BackendService.swift
//  Twofold
//
//  All auth + database access to Supabase lives in `BackendService`. Row structs mirror the DB
//  schema (snake_case columns via explicit CodingKeys) and are mapped to/from the app's existing
//  Person/Place/Couple/Trip/Flight model structs, which stay backend-agnostic.
//
//  This file holds the namespace, the error type, the session token and failure classification.
//  Each domain is an extension in its own `BackendService+<Domain>.swift` beside it.
//

import Foundation
import Supabase

enum BackendError: LocalizedError {
    case notAuthenticated
    case placeLookupFailed
    case avatarURLFailed
    case providerNotConfigured
    case requestFailed(message: String?)
    case accountDeleted
    /// Today's word has already been played, and this couple's plan includes one a day. Not a
    /// failure — the expected end of the free allowance, which the screen answers with an upgrade
    /// rather than an error.
    case wordGuessDailyLimit
    /// Connect 4 is the one game here that cannot be played alone — a board with one player is not
    /// a game, so the screen says so rather than starting one nobody can answer.
    case connectFourNeedsPartner
    /// Both moved behind Premium when chess was withdrawn (20261111000700). Thrown by the RPCs
    /// rather than only checked in the app, so an edited client cannot start one either.
    case connectFourRequiresPremium
    case wordSearchRequiresPremium
    /// Ordinary outcomes of a shared board rather than failures: somebody moved first, the column
    /// filled up, or the game ended while this screen was open.
    case notYourTurn
    case columnFull
    case gameAlreadyFinished
    /// right thing — an invite, or the paywall.
    /// The piece cannot go there. An ordinary part of playing rather than an error, and the board
    /// re-reads rather than retrying.
    case illegalMove

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "You need to be signed in."
        case .placeLookupFailed: "Couldn't resolve that city."
        case .avatarURLFailed: "Couldn't get a URL for that photo."
        case .providerNotConfigured: "This sign-in option isn't set up yet."
        case .requestFailed(let message): message ?? "Something went wrong. Please try again."
        case .accountDeleted: "This account has been deleted and can't be used to sign in. Create a new account to keep using Twofold."
        case .wordGuessDailyLimit: "You've played today's word. A new one arrives tomorrow."
        case .connectFourNeedsPartner: "Connect 4 needs both of you. Invite your partner to play."
        case .connectFourRequiresPremium: "Connect 4 is part of Twofold Premium."
        case .wordSearchRequiresPremium: "Word Search is part of Twofold Premium."
        case .notYourTurn: "It's not your turn yet."
        case .columnFull: "That column is full."
        case .gameAlreadyFinished: "This game has finished."
        case .illegalMove: "That piece can't move there."
        }
    }
}

enum BackendService {

    static var currentUserID: UUID? {
        supabase.auth.currentSession?.user.id
    }

    /// How this account can sign in — "email", "apple", "google" — read from the session already
    /// on disk, so it costs nothing and needs no await.
    ///
    /// The distinction it exists for is "has a password" versus "has a provider", which is not the
    /// same as "signed in with a provider *this* time". An account can hold several identities: one
    /// created with an address and a password, later used with Apple, genuinely has a password to
    /// change. So callers should ask whether this contains "email", never whether it contains
    /// anything else — `AccountView` is the one that cares.
    ///
    /// Empty when the session carries no identities, which is not evidence of anything. It is the
    /// cached copy from the last token refresh, fine for choosing which controls to draw and not a
    /// thing to enforce on: the server decides what a session may actually do.
    static var currentUserSignInProviders: [String] {
        supabase.auth.currentSession?.user.identities?.map(\.provider) ?? []
    }

    /// The signed-in account's email, for identifying this user in third-party dashboards that
    /// otherwise only see the opaque Supabase UUID. Not used for anything the app itself decides.
    static var currentUserEmail: String? {
        supabase.auth.currentSession?.user.email
    }

    /// Where `freshAccessToken()` gets its session. A test hands in its own.
    nonisolated(unsafe) static var validatedAccessToken: @Sendable () async -> String? = {
        try? await supabase.auth.session.accessToken
    }

    /// Forwarded as the `Authorization` header when calling Edge Functions that need to know
    /// who's calling (e.g. `resolve-flight`/`add-flight`/`refresh-flight` — see
    /// `AeroFlightService`) so the function can build a request-scoped, RLS-respecting client.
    ///
    /// From `auth.session`, which refreshes an expired token before handing it over. This used to
    /// read `auth.currentSession`, which returns whatever is on disk unchecked: database calls go
    /// through the SDK and refresh, but these hand-built requests do not, so the first photo
    /// signing or partner notification after a long time in the background could go out with an
    /// expired token and 401 — signing reported it as "unavailable", notifying swallowed it.
    /// Called once per request, not per chunk: see the auth-lock note in `RootView`.
    static func freshAccessToken() async -> String? {
        await validatedAccessToken()
    }

    /// Thrown when an update matched no row. Distinct from a thrown refusal because PostgREST does
    /// not raise one: an UPDATE blocked by RLS is not an error, it simply sees no rows and reports
    /// success with none affected. Verified against the policies — an INSERT gives 42501, an
    /// UPDATE gives zero rows and nothing else.
    ///
    /// Which means a caller that only catches errors will believe a refused edit saved. That is
    /// exactly the silent loss this whole change is about, so the absence has to be turned into a
    /// presence here, once, rather than remembered at each call site.
    struct WriteAffectedNoRows: LocalizedError {
        var errorDescription: String? { "That change wasn't saved." }
    }

    // MARK: - Classifying a failed write

    /// True when the server refused a write outright, rather than failing to hear it.
    ///
    /// The difference decides whether an optimistic local edit may stand. A dropped connection is
    /// temporary — the edit is right, and AppModel's outbox (`PendingWriteStore`) sends it again
    /// later, which is what makes editing work offline. An RLS refusal is permanent: retrying
    /// changes nothing, so keeping the edit on screen shows somebody a change that exists nowhere
    /// and will vanish at the next refresh.
    ///
    /// Matched on the error types themselves: PostgREST's `42501` (insufficient_privilege, which is
    /// also how a deleted account is refused), an HTTP 403 from PostgREST or an Edge Function, and
    /// `storage-url` declining a photo. It used to match on the error's description, which for the
    /// errors the SDK throws never contains the status code, and could not see a storage refusal
    /// at all — so a refused photo upload was kept as "pending" and retried for ever.
    ///
    /// 401 is deliberately not a refusal: it is what an expired access token gets, which the next
    /// attempt with a refreshed one fixes. Anything else — including every network error — is
    /// treated as temporary, because guessing wrong in that direction only costs a retry, where
    /// guessing wrong the other way throws away somebody's writing.
    static func isPermanentRefusal(_ error: Error) -> Bool {
        switch error {
        case is WriteAffectedNoRows:
            return true
        case let error as PostgrestError:
            return error.code == "42501"
        case let error as HTTPError:
            return error.response.statusCode == 403
        case FunctionsError.httpError(let code, _):
            return code == 403
        case EdgeFunctions.Failure.status(let code, _, _):
            return code == 403
        case R2Storage.StorageError.refused:
            return true
        default:
            return false
        }
    }

    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    static func unsubscribe(_ channel: RealtimeChannelV2) async {
        await supabase.removeChannel(channel)
    }
}
