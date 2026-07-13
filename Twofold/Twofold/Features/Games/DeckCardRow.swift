//
//  DeckCardRow.swift
//  Twofold
//
//  One self-contained deck card — display plus all its tap routing (start/resume, jump straight
//  to results once both partners are done, or the Premium gate) — reused by TopicDetailView,
//  GameTypeDecksView, and AllDecksBrowseView so none of them duplicate the branching between
//  "new/in progress", "completed by both", and "locked behind Premium". Must be hosted inside a
//  NavigationStack.
//
//  Resetting/editing answers for a completed deck lives in GameResultsView's own toolbar menu
//  now, not here — tapping a completed card should go straight to the results it already has,
//  not stop at a "view or reset?" prompt first.
//

import SwiftUI

struct DeckCardRow: View {
    let deck: GameDeck
    let progress: DeckProgress?
    /// Shows the deck's topic instead of its game type — used by cross-topic lists (one game
    /// type across every topic, or the all-decks browser) where the game type is either already
    /// implied by the screen or less useful than knowing which topic this deck belongs to.
    var showsTopicPill = false

    @Environment(AppModel.self) private var appModel
    @State private var showingPremiumGate = false

    private var isLocked: Bool { appModel.isDeckLocked(deck) }
    private var bothCompleted: Bool { progress?.bothCompleted ?? false }

    var body: some View {
        Group {
            if isLocked {
                Button { showingPremiumGate = true } label: { content }
                    .buttonStyle(.plain)
            } else if !appModel.partnerConnected {
                content
            } else if bothCompleted, let progress {
                NavigationLink {
                    gameDestinationView(gameType: deck.gameType, sessionID: progress.sessionID, title: deck.title)
                } label: { content }
                    .buttonStyle(.plain)
            } else {
                NavigationLink { DeckEntryView(deck: deck) } label: { content }
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingPremiumGate) {
            DeckPremiumGateView(deck: deck)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    if showsTopicPill, let topic = GameTopic(rawValue: deck.topic) {
                        PillBadge(text: topic.displayName, tint: topic.color)
                    } else {
                        PillBadge(text: deck.gameType.shortLabel, tint: deck.gameType.iconGradient.first ?? Theme.skyBlue)
                    }
                    Text(deck.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                    if bothCompleted {
                        Label("Completed", systemImage: "checkmark.seal.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.leafGreen)
                    } else {
                        Text("\(deck.questionCount) question\(deck.questionCount == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }

                Spacer(minLength: 0)

                if isLocked {
                    ZStack {
                        Circle().fill(Theme.subtleInk.opacity(0.12))
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.subtleInk)
                    }
                    .frame(width: 30, height: 30)
                } else {
                    Text(deck.emoji).font(.title2)
                }
            }

            HStack(spacing: 0) {
                // ZStack (not HStack's negative spacing) so draw order can put "me" on top
                // regardless of left-to-right position — otherwise partner's avatar, added
                // second, paints over my bottom-trailing checkmark badge whenever both overlap.
                ZStack(alignment: .leading) {
                    avatarWithTick(person: appModel.partner, completed: progress?.partnerCompleted ?? false)
                        .offset(x: 24)
                    avatarWithTick(person: appModel.currentUser, completed: progress?.myCompleted ?? false)
                }
                .frame(width: 56, height: 32, alignment: .leading)

                Spacer(minLength: 0)
                if !isLocked {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(bothCompleted ? Theme.leafGreen.opacity(0.1) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            // A completed deck's pale green fill barely reads as different from the page
            // background on its own — a green edge (instead of the generic neutral one) gives
            // it real separation and doubles as a second "done" cue alongside the checkmark tick.
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(bothCompleted ? Theme.leafGreen.opacity(0.5) : Theme.subtleInk.opacity(0.12), lineWidth: bothCompleted ? 1.5 : 1)
        }
        .opacity(isLocked || !appModel.partnerConnected ? 0.75 : 1)
        .contentShape(Rectangle())
    }

    private func avatarWithTick(person: Person, completed: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(person: person, size: 32, showsRing: true)
            if completed {
                ZStack {
                    Circle().fill(Theme.leafGreen)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Theme.cardBackground, lineWidth: 2))
            }
        }
    }
}
