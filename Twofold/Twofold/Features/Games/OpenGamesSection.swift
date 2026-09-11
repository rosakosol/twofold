//
//  OpenGamesSection.swift
//  Twofold
//
//  What is already on, at the top of the Games tab.
//
//  Five games were added that have no deck list to surface them. A sudoku left half-solved, a word
//  search three words short, a chess game where the partner has moved — none of those appeared
//  anywhere except by opening the game and finding out. The games plan called this out before any
//  of them existed: a board where your partner has moved is the strongest re-engagement surface
//  this app has, and it had nowhere to live.
//
//  Deliberately not the conversation games. Those already have "Your turn" as a filter pill on the
//  same screen, and listing them here as well would be two counts of the same thing on one page,
//  free to disagree.
//

import SwiftUI

struct OpenGamesSection: View {
    let games: [BackendService.OpenGame]

    /// Only shown when there is something on. An empty "Playing now" heading is a section telling
    /// you about nothing, at the top of the screen, every time you open the tab.
    var body: some View {
        if !games.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Playing now")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    if yourTurnCount > 0 {
                        Text("\(yourTurnCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.heartRed, in: Capsule())
                            .accessibilityLabel("\(yourTurnCount) waiting for you")
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(games) { game in
                            NavigationLink {
                                gameDestinationView(gameType: game.gameType, sessionID: game.id)
                            } label: {
                                card(game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Room for the shadow, which a scroll view otherwise clips against its own edge.
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var yourTurnCount: Int { games.count { $0.isMyTurn } }

    private func card(_ game: BackendService.OpenGame) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: game.gameType.icon)
                    .font(.caption)
                    .foregroundStyle(Theme.skyBlueText)
                Text(game.gameType.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }

            // The difficulty or theme, where there is one. "Sudoku" alone does not say which of the
            // four, and opening the wrong one is the whole of the annoyance this card removes.
            if let label = game.label {
                Text(label.capitalized)
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }

            Spacer(minLength: 0)

            Text(game.isMyTurn ? "Your turn" : "Waiting on them")
                .font(.caption.weight(game.isMyTurn ? .bold : .regular))
                .foregroundStyle(game.isMyTurn ? Theme.heartRedText : Theme.subtleInk)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 150, height: 96, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        // A ring rather than a fill on the ones that need you: a card whose whole background
        // changes colour reads as a different kind of card, where this is the same card with
        // something waiting in it.
        .overlay {
            if game.isMyTurn {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.heartRed.opacity(0.55), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
