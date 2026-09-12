//
//  OfflineNoticeView.swift
//  Twofold
//
//  Shown once when the app opens with no connection.
//
//  Offline the app is genuinely usable — memories, trips, drawings and most games all work, and
//  everything queues to sync — but nothing said so, and a screen full of last-known data with no
//  explanation reads as an app that has half-loaded and stalled. This says which half is missing
//  and that the rest will catch up on its own, so the answer to "is it broken?" is on screen
//  rather than inferred.
//
//  "Most games" is the part worth keeping honest. This screen used to promise "play games" flatly,
//  which was true when the only games were the decks and stopped being true when Connect 4 and
//  Chess arrived — those validate every move server-side, so offline they do not work at all.
//  A list that overpromises is worse than no list: it sends somebody to a board that will refuse
//  them, having just told them it would be fine. See `available`/`unavailable` for the three ways
//  a game behaves here.
//

import SwiftUI

struct OfflineNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    /// What still works, in the order someone is most likely to reach for it.
    ///
    /// The games are named by type rather than lumped into one "play games" line, because they do
    /// not behave the same way offline and the old line promised all of them. Three kinds:
    ///
    ///   * The question and conversation decks work completely — `GameSessionStore` can build a
    ///     session from the on-device catalogue and queues every answer.
    ///   * The generated puzzles work once they exist. The grid comes from a uuid handed out when
    ///     the session started, and each device builds the same puzzle from it without fetching
    ///     anything — so carrying one on is free, and starting a fresh one still needs the round
    ///     trip that hands out that uuid.
    ///   * Connect 4 and Chess do not work at all. Every move is validated and stored server-side
    ///     before the board moves; there is nothing to queue, because a move's legality isn't this
    ///     device's to decide.
    private let available: [(icon: String, text: String)] = [
        ("gamecontroller.fill", "Play question and conversation decks"),
        ("square.grid.3x3.fill", "Carry on a Sudoku, Word Guess or Word Search you've started"),
        ("photo.on.rectangle.angled", "Add memories, with photos"),
        ("airplane", "Add trips"),
        ("scribble.variable", "Draw on your pad"),
    ]

    private let unavailable: [(icon: String, text: String)] = [
        ("arrow.left.arrow.right", "Connect 4 and Chess — every move needs a connection"),
        ("plus.circle", "Starting a new Sudoku, Word Guess or Word Search"),
        ("magnifyingglass", "Searching for flights or places"),
        ("arrow.triangle.2.circlepath", "Live flight tracking and your partner's updates"),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Theme.skyBlue.opacity(0.18))
                                .frame(width: 116, height: 116)
                                .blur(radius: 16)
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(Theme.skyBlue)
                        }

                        Text("You're offline")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Twofold still works. Anything you add is saved on this device and sent as soon as you're back online.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    section(title: "You can still", rows: available, tint: Theme.leafGreen, symbol: "checkmark")
                    section(title: "Not until you're back", rows: unavailable, tint: Theme.subtleInk, symbol: nil)
                }
                .padding(.top, Theme.Spacing.xl)
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func section(title: String, rows: [(icon: String, text: String)], tint: Color, symbol: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Theme.subtleInk)

            ForEach(rows, id: \.text) { row in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: symbol ?? row.icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    Text(row.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        OfflineNoticeView()
    }
}
