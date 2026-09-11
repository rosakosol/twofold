//
//  ChessBoardView.swift
//  Twofold
//
//  Sixty-four squares, tapped rather than dragged.
//
//  Tap to pick a piece up, tap again to put it down. A drag across a board this size means a 40pt
//  target for every destination and a queen dropped somewhere unintended whenever a thumb slips —
//  and unlike the word search, where a wrong drag simply finds nothing, a wrong chess move is
//  submitted, legal and permanent.
//
//  The board is drawn from the black player's side when they are black, so "my pieces are at the
//  bottom" is true for both of them. That is the one orientation rule chess has and the one thing
//  that makes a shared board readable to two people at once.
//
//  Pieces are the Unicode figurines rather than bundled art. The solid glyphs are used for both
//  colours and then tinted, rather than the outline set for white: an outlined white king on a
//  light square is nearly invisible, where a tinted solid one reads at any size, in either theme,
//  and scales with Dynamic Type for free.
//

import ChessKit
import SwiftUI

struct ChessBoardView: View {
    let board: Board
    /// Which way up to draw it. Nil before the session has loaded, in which case white's view is
    /// as good a guess as any.
    let myColor: Piece.Color?
    let selected: Square?
    let legalDestinations: [Square]
    let lastMove: (from: Square, to: Square)?
    let isInteractive: Bool
    let onTap: (Square) -> Void

    /// Ranks from the player's own side: 8 down to 1 for white, 1 up to 8 for black.
    private var ranks: [Int] {
        myColor == .black ? Array(1...8) : Array((1...8).reversed())
    }

    private var files: [Square.File] {
        myColor == .black ? Square.File.allCases.reversed() : Square.File.allCases
    }

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width / 8
            VStack(spacing: 0) {
                ForEach(ranks, id: \.self) { rank in
                    HStack(spacing: 0) {
                        ForEach(files, id: \.self) { file in
                            square(at: Square("\(file.rawValue)\(rank)"), side: side)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func square(at square: Square, side: CGFloat) -> some View {
        let piece = board.position.piece(at: square)
        let isDestination = legalDestinations.contains(square)

        return ZStack {
            Rectangle().fill(squareColor(square))

            if isLastMove(square) {
                // The last move, marked on both squares. On a game played across a day, the first
                // question on opening it is always "what did they just do".
                Rectangle().fill(Theme.skyBlue.opacity(0.28))
            }
            if selected == square {
                Rectangle().fill(Theme.leafGreen.opacity(0.42))
            }
            if isInCheck(square) {
                // Only the king in check, and only while it is. A board that highlights every
                // attacked piece is a board playing the game for you.
                Rectangle().fill(Theme.heartRed.opacity(0.4))
            }

            if let piece {
                Text(Self.glyph(for: piece.kind))
                    .font(.system(size: side * 0.72))
                    .foregroundStyle(piece.color == .white ? Self.whitePiece : Self.blackPiece)
                    // A hairline in the opposite colour, so a white piece on a light square and a
                    // black one on a dark square both keep an edge.
                    .shadow(color: piece.color == .white ? .black.opacity(0.45) : .white.opacity(0.25), radius: 0.6)
            }

            if isDestination {
                // A dot on an empty square, a ring around an occupied one — the difference between
                // "you may go here" and "you may take this".
                if piece == nil {
                    Circle()
                        .fill(Theme.leafGreen.opacity(0.55))
                        .frame(width: side * 0.28, height: side * 0.28)
                } else {
                    Circle()
                        .strokeBorder(Theme.leafGreen.opacity(0.8), lineWidth: side * 0.08)
                        .padding(side * 0.04)
                }
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .onTapGesture { if isInteractive { onTap(square) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: square, piece: piece))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    private func squareColor(_ square: Square) -> Color {
        // Light and dark squares, kept deliberately low-contrast against the pieces: a board whose
        // squares compete with its pieces is harder to read than one whose squares recede.
        isLight(square) ? Self.lightSquare : Self.darkSquare
    }

    private func isLight(_ square: Square) -> Bool {
        let fileIndex = Square.File.allCases.firstIndex(of: square.file) ?? 0
        return (fileIndex + square.rank.value) % 2 == 1
    }

    private func isLastMove(_ square: Square) -> Bool {
        guard let lastMove else { return false }
        return square == lastMove.from || square == lastMove.to
    }

    private func isInCheck(_ square: Square) -> Bool {
        guard case .check(let color) = board.state else { return false }
        guard let piece = board.position.piece(at: square) else { return false }
        return piece.kind == .king && piece.color == color
    }

    private func label(for square: Square, piece: Piece?) -> String {
        guard let piece else { return "\(square.notation), empty" }
        return "\(square.notation), \(piece.color == .white ? "white" : "black") \(Self.name(for: piece.kind))"
    }

    // MARK: - Appearance

    static let lightSquare = Color(light: "EDE4D3", dark: "5A5348")
    static let darkSquare = Color(light: "B58863", dark: "3A342C")
    static let whitePiece = Color(light: "FFFFFF", dark: "F5F2EC")
    static let blackPiece = Color(light: "2B2622", dark: "16120F")

    /// The solid figurines for both colours — see the note at the top of the file.
    ///
    /// Each carries U+FE0E, the text presentation selector, and it is doing real work: without it
    /// iOS substitutes an emoji font for U+265F and draws the pawn as a fixed black image that
    /// ignores `foregroundStyle` entirely. Every white pawn on the board came out black, and only
    /// the pawns — the other five glyphs render as text either way, so the board looked almost
    /// right, which is the worst way for it to be wrong.
    static func glyph(for kind: Piece.Kind) -> String {
        let figurine: String = switch kind {
        case .king: "♚"
        case .queen: "♛"
        case .rook: "♜"
        case .bishop: "♝"
        case .knight: "♞"
        case .pawn: "♟"
        }
        return figurine + "\u{FE0E}"
    }

    static func name(for kind: Piece.Kind) -> String {
        switch kind {
        case .king: "king"
        case .queen: "queen"
        case .rook: "rook"
        case .bishop: "bishop"
        case .knight: "knight"
        case .pawn: "pawn"
        }
    }
}

#Preview("Opening") {
    ChessBoardView(
        board: Board(),
        myColor: .white,
        selected: .e2,
        legalDestinations: [.e3, .e4],
        lastMove: nil,
        isInteractive: true,
        onTap: { _ in }
    )
    .padding()
    .background(Theme.backgroundGradient)
}

#Preview("From black's side") {
    var board = Board()
    board.move(pieceAt: .e2, to: .e4)
    return ChessBoardView(
        board: board,
        myColor: .black,
        selected: nil,
        legalDestinations: [],
        lastMove: (.e2, .e4),
        isInteractive: true,
        onTap: { _ in }
    )
    .padding()
    .background(Theme.backgroundGradient)
}
