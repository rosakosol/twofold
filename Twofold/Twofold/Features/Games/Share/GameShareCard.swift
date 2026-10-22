//
//  GameShareCard.swift
//  Twofold
//
//  The one game share card (SHARE_REDESIGN.md §3): a fixed 360 × 450pt (4:5) card in the game's own
//  colour, or Night or Paper, exported at 3x as a 1080 × 1350px PNG. One layout per game type, in
//  place of the three answer layouts, the varying heights and the per-game styles before it.
//
//  Every colour comes from `Theme.Share`. Text on colour is full white, never faded.
//

import SwiftUI

/// Which game a card is for: its colour, chip name and icon.
enum GameShareKind: Equatable {
    case deepConversation
    case thisOrThat
    case moreLikely
    case trivia
    /// Word Guess and the other puzzles share one gradient; the chip carries the game's own name.
    case puzzle(name: String)
    /// Connect 4 and drawings borrow the puzzles' gradient for now, with their own chip icon.
    case connectFour
    case drawing

    init(_ gameType: GameType) {
        switch gameType {
        case .deepConversations: self = .deepConversation
        case .thisOrThat: self = .thisOrThat
        case .moreLikely: self = .moreLikely
        case .triviaBattle: self = .trivia
        case .connectFour: self = .connectFour
        default: self = .puzzle(name: gameType.displayName)
        }
    }

    var name: String {
        switch self {
        case .deepConversation: "Deep Conversation"
        case .thisOrThat: "This or That"
        case .moreLikely: "Who's More Likely To"
        case .trivia: "Trivia Battle"
        case .puzzle(let name): name
        case .connectFour: "Connect 4"
        case .drawing: String(localized: "Drawing")
        }
    }

    var icon: String {
        switch self {
        case .deepConversation: "bubble.left.and.bubble.right"
        case .thisOrThat: "arrow.left.arrow.right"
        case .moreLikely: "person.2"
        case .trivia: "questionmark.circle"
        case .puzzle: "square.grid.2x2"
        case .connectFour: "circle.grid.2x2"
        case .drawing: "pencil"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .deepConversation: Theme.Share.deepConversation
        case .thisOrThat: Theme.Share.thisOrThat
        case .moreLikely: Theme.Share.moreLikely
        case .trivia: Theme.Share.trivia
        case .puzzle, .connectFour, .drawing: Theme.Share.puzzle
        }
    }
}

/// One Word Guess tile on the card. `unused` is a row nobody needed.
enum GameShareTile: Equatable {
    case correct, present, absent, unused
}

/// What sits between the header and the footer.
enum GameShareContent: Equatable {
    struct Answer: Equatable {
        let name: String
        let text: String
    }
    struct ScoreColumn: Equatable {
        /// "8", or a solve time like "4:12".
        let value: String
        let name: String
        /// Sudoku's hints and checks, when any were used.
        var note: String? = nil
    }
    struct PuzzlePlayer: Equatable {
        let name: String
        /// "4/6", or "Missed".
        let result: String
        let solved: Bool
        /// Always six rows of five.
        let rows: [[GameShareTile]]
    }

    /// Deep Conversation: one card per question.
    case questionAndAnswers(deck: String, question: String, answers: [Answer])
    /// This or That and Who's More Likely To.
    case similarity(deck: String, percent: Int)
    /// Trivia Battle (scores) and Sudoku (times): two big values side by side, and a caption.
    case score(deck: String, columns: [ScoreColumn], caption: String)
    /// Word Guess.
    case puzzle(subtitle: String, players: [PuzzlePlayer])
    /// Connect 4: the board as it stands, row 0 at the top, and whose pieces are whose. `winning`
    /// holds the cells of the four in a row once somebody has one.
    case connectFour(status: String, cells: [ConnectFourBoard.Disc?], winning: Set<Int>, firstName: String, secondName: String)
    /// One drawing, or both side by side.
    case drawings([Drawing])

    struct Drawing: Equatable {
        let name: String
        let image: UIImage
    }
}

struct GameShareCard: View {
    let kind: GameShareKind
    let look: ShareCardStyle
    let content: GameShareContent
    let me: Person
    let partner: Person

    static let size = CGSize(width: 360, height: 450)

    var body: some View {
        VStack(spacing: 16) {
            header
            Spacer(minLength: 0)
            contentView
                .layoutPriority(1)
            Spacer(minLength: 0)
            footer
        }
        .padding(EdgeInsets(top: 22, leading: 22, bottom: 20, trailing: 22))
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(ink)
        .background { background }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(border, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if case .drawings(let drawings) = content {
            let names = drawings.map { String(localized: "\($0.name)'s drawing") }
            return ListFormatter.localizedString(byJoining: names) + ", twofold"
        }
        return String(localized: "\(kind.name) result shared by \(me.name) and \(partner.name), twofold")
    }

    // MARK: - Look (§3.2)

    @ViewBuilder
    private var background: some View {
        switch look {
        case .deck:
            ZStack {
                kind.gradient
                BrandHighlight()
            }
        case .night: Theme.Share.night
        case .paper: Theme.Share.paper
        }
    }

    private var border: Color? {
        switch look {
        case .deck: nil
        case .night: Theme.Share.nightLine
        case .paper: Theme.Share.paperLine
        }
    }

    private var ink: Color {
        switch look {
        case .deck: .white
        case .night: Theme.Share.nightInk
        case .paper: Theme.Share.paperInk
        }
    }

    /// Never faded on colour: full white there.
    private var muted: Color {
        switch look {
        case .deck: .white
        case .night: Theme.Share.nightMuted
        case .paper: Theme.Share.paperMuted
        }
    }

    private var panel: Color {
        switch look {
        case .deck: Theme.Share.onColourPanel
        case .night: Theme.Share.nightPanel
        case .paper: Theme.Share.paperPanel
        }
    }

    private var number: Color {
        switch look {
        case .deck: .white
        case .night: Theme.Share.nightNumber
        case .paper: Theme.Share.stampInk
        }
    }

    private var heart: Color {
        switch look {
        case .deck: .white
        case .night: Theme.Share.nightHeart
        case .paper: Theme.Share.paperHeart
        }
    }

    // MARK: - Header (§3.4)

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: kind.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text(kind.name)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 12))
            .background {
                Capsule().fill(look == .deck ? AnyShapeStyle(Theme.Share.onColourChip) : AnyShapeStyle(kind.gradient))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Content (§3.5)

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case let .questionAndAnswers(deck, question, answers):
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(deck)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(muted)
                    Text(question)
                        .font(.system(size: 20, weight: .bold))
                        .tracking(-0.2)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                }
                ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(answer.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(muted)
                        // Scales down to 14pt, then truncates: the card stays 4:5. The full answer
                        // is in "Copy as text".
                        Text(answer.text)
                            .font(.system(size: 16, design: .serif))
                            .lineSpacing(5.6)
                            .lineLimit(3)
                            .minimumScaleFactor(0.875)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(EdgeInsets(top: 11, leading: 14, bottom: 12, trailing: 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case let .similarity(deck, percent):
            VStack(spacing: 4) {
                Text(deck)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                Text("\(percent)%")
                    .font(.system(size: 96, weight: .bold))
                    .tracking(-3.84)
                    .foregroundStyle(number)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("answer similarity")
                    .font(.system(size: 17))
                    .foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity)

        case let .score(deck, columns, caption):
            VStack(spacing: 18) {
                Text(deck)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        scoreColumn(column)
                    }
                }
                Text(caption)
                    .font(.system(size: 15))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

        case let .connectFour(status, cells, winning, firstName, secondName):
            VStack(spacing: 12) {
                Text(status)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.17)
                    .lineLimit(1)
                connectFourBoard(cells, winning: winning)
                HStack(spacing: 20) {
                    legendItem(.second, secondName)
                    legendItem(.first, firstName)
                }
                .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)

        case let .drawings(drawings):
            if drawings.count == 1, let drawing = drawings.first {
                VStack(spacing: 8) {
                    drawingTile(drawing, height: 288, radius: 18)
                    Text("Drawn by \(drawing.name)")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(drawings.enumerated()), id: \.offset) { _, drawing in
                        VStack(spacing: 8) {
                            drawingTile(drawing, height: 244, radius: 16)
                            Text(drawing.name)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                        }
                    }
                }
            }

        case let .puzzle(subtitle, players):
            VStack(spacing: 14) {
                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(muted)
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Array(players.enumerated()), id: \.offset) { _, player in
                        puzzleColumn(player)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func drawingTile(_ drawing: GameShareContent.Drawing, height: CGFloat, radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return Color.white
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Fitted, never cropped: people draw right to the edges.
            .overlay { Image(uiImage: drawing.image).resizable().scaledToFit() }
            .clipShape(shape)
            .overlay {
                if look == .paper { shape.strokeBorder(Theme.Share.paperLine, lineWidth: 1) }
            }
    }

    /// A finished game shows *how* it was won, not only who won: the four in a row get a ring in
    /// the card's ink, and every other piece steps back.
    private func connectFourBoard(_ cells: [ConnectFourBoard.Disc?], winning: Set<Int>) -> some View {
        VStack(spacing: 5) {
            ForEach(0..<ConnectFourBoard.rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<ConnectFourBoard.columns, id: \.self) { column in
                        let index = row * ConnectFourBoard.columns + column
                        let disc = cells.indices.contains(index) ? cells[index] : nil
                        piece(disc)
                            .opacity(!winning.isEmpty && disc != nil && !winning.contains(index) ? 0.35 : 1)
                            .frame(width: 30, height: 30)
                            .overlay {
                                // Just outside the piece, and narrow enough that two neighbouring
                                // rings meet in the 5pt gap rather than overlap.
                                if winning.contains(index) {
                                    Circle().stroke(ink, lineWidth: 2).padding(-1.5)
                                }
                            }
                    }
                }
            }
        }
        .padding(8)
        .background(boardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func piece(_ disc: ConnectFourBoard.Disc?) -> some View {
        if let disc {
            Circle().fill(pieceFill(disc))
        } else if look == .deck {
            Circle().strokeBorder(Theme.Share.tileUnusedOnColour, lineWidth: 1.5)
        } else {
            Circle().fill(look == .night ? Theme.Share.holeNight : Theme.Share.holePaper)
        }
    }

    private var boardFill: Color {
        switch look {
        case .deck: Theme.Share.boardOnColour
        case .night: Theme.Share.boardNight
        case .paper: Theme.Share.boardPaper
        }
    }

    private func pieceFill(_ disc: ConnectFourBoard.Disc) -> Color {
        switch (look, disc) {
        case (.deck, .first): Theme.Share.firstPieceOnColour
        case (.deck, .second): Theme.Share.secondPieceOnColour
        case (.night, .first): Theme.Share.firstPieceNight
        case (.night, .second): Theme.Share.secondPieceNight
        case (.paper, .first): Theme.Share.firstPiecePaper
        case (.paper, .second): Theme.Share.secondPiecePaper
        }
    }

    private func legendItem(_ disc: ConnectFourBoard.Disc, _ name: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(pieceFill(disc)).frame(width: 12, height: 12)
            Text(name).lineLimit(1)
        }
    }

    private func scoreColumn(_ column: GameShareContent.ScoreColumn) -> some View {
        VStack(spacing: 2) {
            Text(column.value)
                .font(.system(size: 76, weight: .bold))
                .tracking(-3.04)
                .foregroundStyle(number)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(column.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if let note = column.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func puzzleColumn(_ player: GameShareContent.PuzzlePlayer) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(player.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(player.result)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.56)
                    .foregroundStyle(player.solved ? number : ink)
            }
            VStack(spacing: 4) {
                ForEach(Array(player.rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, tile in
                            tileView(tile)
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func tileView(_ tile: GameShareTile) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Group {
            if tile == .unused {
                shape.strokeBorder(unusedTileLine, lineWidth: 1.5)
            } else {
                shape.fill(tileFill(tile))
            }
        }
        .frame(width: 17, height: 17)
    }

    /// §3.5's tile table. These yellows are for Word Guess tiles only.
    private func tileFill(_ tile: GameShareTile) -> Color {
        switch (look, tile) {
        case (.deck, .correct): Theme.Share.tileCorrectOnColour
        case (.deck, .present): Theme.Share.tilePresentOnColour
        case (.deck, _): Theme.Share.tileAbsentOnColour
        case (.night, .correct): Theme.Share.tileCorrectNight
        case (.night, .present): Theme.Share.tilePresentNight
        case (.night, _): Theme.Share.tileAbsentNight
        case (.paper, .correct): Theme.Share.tileCorrectPaper
        case (.paper, .present): Theme.Share.tilePresentPaper
        case (.paper, _): Theme.Share.tileAbsentPaper
        }
    }

    private var unusedTileLine: Color {
        switch look {
        case .deck: Theme.Share.tileUnusedOnColour
        case .night: Theme.Share.tileAbsentNight
        case .paper: Theme.Share.tileAbsentPaper
        }
    }

    // MARK: - Footer (§3.6)

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    avatar(me)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(heart)
                    avatar(partner)
                }
                Text("\(me.name) & \(partner.name)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 19)
                Text("twofold")
                    .font(.system(size: 19, design: .serif))
                    .tracking(-0.19)
            }
        }
    }

    private func avatar(_ person: Person) -> some View {
        AvatarView(person: person, size: 30, showsRing: true)
    }
}

extension GameShareCard {
    /// The card as the PNG that gets shared: 1080 × 1350px at 3x (§3.1).
    @MainActor
    func renderedImage() -> UIImage? {
        // An explicit scheme because the renderer ignores the phone's and defaults to light; every
        // colour on the card is fixed anyway, so this only keeps AvatarView's placeholder steady.
        let renderer = ImageRenderer(content: self.environment(\.colorScheme, .dark))
        renderer.scale = 3
        return renderer.uiImage
    }
}

#Preview("Looks") {
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            ForEach(ShareCardStyle.allCases, id: \.self) { look in
                GameShareCard(
                    kind: .deepConversation,
                    look: look,
                    content: .questionAndAnswers(
                        deck: "What Do You Want Me to Know?",
                        question: "What's something you've never told me about how you feel when we're apart?",
                        answers: [
                            .init(name: "Rosa", text: "That the quiet evenings are the hardest, more than the goodbyes."),
                            .init(name: "Ewin", text: "I keep a list of things to show you when you're here."),
                        ]
                    ),
                    me: MockData.rosa,
                    partner: MockData.dara
                )
            }
        }
        .padding()
    }
    .background(Color.black)
}
