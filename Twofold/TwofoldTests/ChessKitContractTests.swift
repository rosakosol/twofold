//
//  ChessKitContractTests.swift
//  TwofoldTests
//
//  What this app needs ChessKit to do, asserted against the version that is pinned.
//
//  It is the app's first dependency that is not infrastructure — everything else here talks to a
//  service, and this one *is* the rules of the game. The games plan accepted it deliberately: legal
//  move generation is the hard part of chess (castling through check, en passant exposing a pin,
//  stalemate that looks like checkmate) and none of it is distinctive to Twofold.
//
//  One finding here decides the shape of the whole game. `Board.state` is only meaningful *after a
//  move*: `updateState` at init takes `moveColor = position.sideToMove` and then assesses
//  `moveColor.opposite`, so a board built from a FEN evaluates the side that has just moved rather
//  than the side to move. A stalemated position loaded from FEN reads `.active`.
//
//  So the app rebuilds a game by replaying its moves and never by loading a stored position — the
//  same conclusion Connect 4 reached for a different reason. `itDetectsStalemateWhenReachedByAMove`
//  below is what pins it.
//
//  So this is a contract rather than a test of somebody else's library. It pins the handful of
//  behaviours the app relies on, so a version bump that changes any of them fails here rather than
//  in somebody's game. The dependency is pinned `upToNextMinorVersion` for the same reason: 0.x
//  means the API may move, and a board that quietly stops detecting checkmate is not a failure
//  anybody notices quickly.
//

import ChessKit
import Testing
@testable import Twofold

struct ChessKitContractTests {

    @Test func aFreshBoardIsTheStandardPosition() {
        let board = Board()
        #expect(board.position.pieces.count == 32)
        #expect(board.position.sideToMove == .white)
        #expect(board.state == .active)
    }

    @Test func itKnowsWhereAPieceMayGo() {
        let board = Board()
        #expect(Set(board.legalMoves(forPieceAt: .e2)) == Set([.e3, .e4]))
        #expect(board.legalMoves(forPieceAt: .e1).isEmpty, "a boxed-in king has nowhere to go")
    }

    @Test func itRefusesAnIllegalMove() {
        var board = Board()
        #expect(!board.canMove(pieceAt: .a1, to: .a8))
        #expect(board.canMove(pieceAt: .g1, to: .f3))
        // Called outside `#expect`: the macro captures what it is given immutably, and `move` is
        // mutating — so inlining it does not compile.
        let refused = board.move(pieceAt: .a1, to: .a8)
        #expect(refused == nil, "an illegal move changes nothing")
    }

    /// The whole reason for taking a dependency. A pinned piece that may not step aside is the rule
    /// a hand-written implementation gets wrong, and gets wrong silently.
    @Test func aPinnedPieceCannotExposeItsKing() throws {
        // Black king e8, black knight e7, white rook e1: the knight is pinned down the e-file.
        let position = try #require(Position(fen: "4k3/4n3/8/8/8/8/8/4R1K1 b - - 0 1"))
        let board = Board(position: position)
        #expect(board.legalMoves(forPieceAt: .e7).isEmpty, "moving the knight would expose the king")
    }

    @Test func itDetectsCheckmate() throws {
        // Back-rank mate in one: Qe5-e8.
        var board = Board(position: try #require(Position(fen: "6k1/5ppp/8/4Q3/8/8/8/6K1 w - - 0 1")))
        // Outside the macro, as above: `#require` captures its argument immutably.
        let played = board.move(pieceAt: .e5, to: .e8)
        let move = try #require(played)
        #expect(move.checkState == .checkmate)
        #expect(board.state == .checkmate(color: .black), "black is the side mated")
    }

    /// Checkmate and stalemate are one legal move apart and mean opposite things — a win against a
    /// draw. Anything that collapses them is the single worst thing this dependency could do.
    ///
    /// Reached by playing the move rather than by loading the position, which is not a stylistic
    /// choice: see the note at the top of this file. The same position loaded straight from FEN
    /// reports `.active`, and that is exactly why the game replays its move log.
    @Test func itDetectsStalemateWhenReachedByAMove() throws {
        // Black king h8, white king f7, white queen g4. Qg4-g6 leaves black with no legal move and
        // not in check.
        var board = Board(position: try #require(Position(fen: "7k/5K2/8/8/6Q1/8/8/8 w - - 0 1")))
        let played = board.move(pieceAt: .g4, to: .g6)
        #expect(played != nil)
        #expect(board.state == .draw(reason: .stalemate))
        #expect(board.state != .checkmate(color: .black))
    }

    /// The finding above, pinned from the other side: a terminal position loaded from FEN does not
    /// report itself as terminal. Asserted so that the reason the game replays its moves is written
    /// down as behaviour rather than only as a comment — and so a future version that fixes this
    /// fails here and gets noticed, rather than silently making the replay redundant.
    @Test func aPositionLoadedFromFenDoesNotReportItsOwnEndgame() throws {
        let stalemate = try #require(Position(fen: "7k/5K2/6Q1/8/8/8/8/8 b - - 0 1"))
        #expect(Board(position: stalemate).state == .active, "still true as of 0.17.0")
    }

    @Test func itDetectsADrawOnInsufficientMaterial() throws {
        // Two bare kings: nobody can ever mate, so the game is over however long they play.
        let board = Board(position: try #require(Position(fen: "7k/8/8/8/8/8/8/K7 w - - 0 1")))
        #expect(board.state == .draw(reason: .insufficientMaterial))
    }

    /// Promotion is a two-step in this library — the move lands, the board reports `.promotion`,
    /// and the caller completes it. The app has to know that, because a pawn that reaches the last
    /// rank and stops there is a board nobody can move on.
    @Test func promotionIsReportedAndCompleted() throws {
        var board = Board(position: try #require(Position(fen: "8/P6k/8/8/8/8/8/K7 w - - 0 1")))
        let played = board.move(pieceAt: .a7, to: .a8)
        let move = try #require(played)
        guard case .promotion = board.state else {
            Issue.record("expected a promotion, got \(board.state)")
            return
        }
        board.completePromotion(of: move, to: .queen)
        #expect(board.position.piece(at: .a8)?.kind == .queen)
    }

    /// Positions and moves travel between the two devices, so a round trip has to be exact — a
    /// dropped castling right or en-passant square is a different position that looks identical on
    /// the board.
    @Test func fenRoundTripsExactly() throws {
        let fen = "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2"
        #expect(try #require(Position(fen: fen)).fen == fen)
    }

    @Test func squaresRoundTripThroughTheirNames() {
        // The move log stores squares by name ("e2e4"), so this is the wire format's own contract.
        for square in Square.allCases {
            #expect(Square(square.notation) == square, "\(square.notation) did not round trip")
        }
    }
}
