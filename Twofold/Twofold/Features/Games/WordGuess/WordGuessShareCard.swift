//
//  WordGuessShareCard.swift
//  Twofold
//
//  The two of you on one word, as an image to send: each person's score and the colours of every
//  guess they made, without the letters. That is the convention this kind of game is shared in,
//  and the reason for it holds here too: the card can go to somebody who hasn't played the word
//  yet without telling them what it was.
//
//  Fixed colours, rendered dark (see `WordGuessShareButton`): it is an image that leaves the app,
//  so it looks the same whatever the sender's phone is set to.
//

import SwiftUI

struct WordGuessShareCard: View {
    let mine: WordGuessPlayState
    let theirs: WordGuessPlayState
    let myName: String
    let partnerName: String
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Word Guess")
                    .font(.title3.weight(.bold))
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.subheadline)
                    .opacity(0.8)
            }

            HStack(alignment: .top, spacing: 20) {
                column(name: myName, play: mine)
                column(name: partnerName, play: theirs)
            }

            HStack(spacing: 4) {
                Image("GlobeHeart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                Text("twofold")
                    .font(.newsreader(size: 14))
            }
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameType.wordGuess.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func column(name: String, play: WordGuessPlayState) -> some View {
        let summary = WordGuessSummary(guessCount: play.guesses.count, solved: play.isSolved, elapsed: play.elapsed)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(WordGuessComparison.scoreText(summary))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(play.guesses.enumerated()), id: \.offset) { _, guess in
                    HStack(spacing: 4) {
                        ForEach(Array(WordGuessEvaluation.marks(guess: guess, answer: play.answer).enumerated()), id: \.offset) { _, mark in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(mark.tileColor)
                                .frame(width: 22, height: 22)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders the card once and offers it to the share sheet. Disabled until the image exists, which
/// is a frame or two after it appears.
struct WordGuessShareButton: View {
    let card: WordGuessShareCard

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Word Guess results", image: Image(uiImage: image))
                ) {
                    label
                }
            } else {
                label.opacity(0.5)
            }
        }
        .buttonStyle(.twofoldPrimary)
        .task { render() }
    }

    private var label: some View {
        Label("Share results", systemImage: "square.and.arrow.up")
            .font(.headline)
    }

    private func render() {
        // A fixed width so the exported image is always the same deliberate size, and
        // `.environment(\.colorScheme,)` because the renderer otherwise draws light whatever the
        // phone is set to (see GameResultsShareView for how that was found).
        let renderer = ImageRenderer(content: card.frame(width: 360).environment(\.colorScheme, .dark))
        renderer.scale = displayScale
        image = renderer.uiImage
    }
}

#Preview {
    let mine = WordGuessPlayState.decoded(from: "wordguess.v1|crane,plant|95", answer: "plant")
    let theirs = WordGuessPlayState.decoded(from: "wordguess.v1|stare,clamp,plain,plant|180", answer: "plant")
    return Group {
        if let mine, let theirs {
            WordGuessShareCard(mine: mine, theirs: theirs, myName: "Dara", partnerName: "Rosa", date: .now)
                .padding()
        }
    }
}
