//
//  CoupleStateOutcome.swift
//  Twofold
//
//  What a couple-state fetch actually told us — as opposed to what `try?` reduces it to.
//
//  `fetchCoupleState()` has three outcomes, not two. It returns a state when the couple is paired,
//  returns nil when the backend says there is no active couple row, and *throws* when the request
//  never completed. The first two are answers; the third is silence.
//
//  Read through `try?` those last two collapse into the same nil, and both call sites took that
//  nil as "the couple was dissolved". So a connection dropping and coming back — Wi-Fi off, Wi-Fi
//  on — could fail the couple fetch, succeed the profile fetch a moment later, and tear down the
//  pairing: "your connection with <partner> has ended", shared trips and memories cleared from the
//  screen, all from a network blip. The next refresh put it back, which is exactly how it was
//  reported: the notice appeared and then the partner's content loaded anyway.
//
//  Nothing here talks to the network. It exists so the distinction has a name and a test, rather
//  than living in a `try?` that reads fine and means something else.
//

import Foundation

enum CoupleStateOutcome: Equatable {
    /// The backend returned a couple. Adopt it.
    case paired(BackendService.CoupleState)
    /// The backend answered, and there is no active couple row. This is the only outcome that
    /// justifies tearing down a pairing.
    case noCouple
    /// The request didn't complete, so we learned nothing. Leave everything exactly as it is —
    /// "couldn't ask" must never be treated as "the answer is no".
    case unknown

    static func == (lhs: CoupleStateOutcome, rhs: CoupleStateOutcome) -> Bool {
        switch (lhs, rhs) {
        case (.noCouple, .noCouple), (.unknown, .unknown): true
        case let (.paired(a), .paired(b)): a.couple.id == b.couple.id
        default: false
        }
    }

    /// The mapping, kept separate from the call so it can be tested without a backend.
    static func from(_ result: Result<BackendService.CoupleState?, Error>) -> CoupleStateOutcome {
        switch result {
        case let .success(state): state.map { .paired($0) } ?? .noCouple
        case .failure: .unknown
        }
    }

    static func fetch() async -> CoupleStateOutcome {
        do {
            return from(.success(try await BackendService.fetchCoupleState()))
        } catch {
            return from(.failure(error))
        }
    }
}
