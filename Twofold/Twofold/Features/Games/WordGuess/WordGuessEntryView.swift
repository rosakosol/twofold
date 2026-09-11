//
//  WordGuessEntryView.swift
//  Twofold
//
//  Word Guess's front door. Stands in for the deck list every other game type opens, in the same
//  way `SudokuDifficultyPickerView` does — there is no bank of content to list.
//
//  It exists rather than the hub card pushing straight into the board because starting one is a
//  round trip that can legitimately refuse: a Plus couple gets one word a day, and "come back
//  tomorrow, or upgrade" is an answer this screen has to be able to give.
//

import SwiftUI

struct WordGuessEntryView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isStarting = false
    @State private var route: UUID?
    @State private var showingPaywall = false
    @State private var errorMessage: String?
    @State private var limitReached = false

    private var isPremium: Bool { appModel.subscriptionTier == "premium" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("The same word on both your phones. Six guesses each, then compare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.subtleInk)

                howItWorks

                if limitReached {
                    limitCard
                } else {
                    startButton
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRedText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                allowanceNote
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(GameType.wordGuess.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { sessionID in
            WordGuessGameView(sessionID: sessionID)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(initialTier: .premium) }
        }
    }

    private var howItWorks: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                rule(.correct, "Right letter, right place.")
                rule(.present, "In the word, somewhere else.")
                rule(.absent, "Not in the word at all.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rule(_ mark: WordGuessMark, _ text: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 5)
                .fill(mark.tileColor)
                .frame(width: 30, height: 30)
                .overlay(
                    Text("A")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(mark.tileTextColor)
                )
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(mark.accessibilityDescription). \(text)")
    }

    private var startButton: some View {
        Button(action: start) {
            HStack(spacing: Theme.Spacing.xs) {
                if isStarting { ProgressView().controlSize(.small).tint(.white) }
                Text("Play today's word")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Theme.primaryButtonGradient, in: Capsule())
        .foregroundStyle(.white)
        .disabled(isStarting)
    }

    /// Shown instead of the button once the server has refused, rather than letting them tap into
    /// the same refusal again.
    private var limitCard: some View {
        SectionCard {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.leafGreen)
                Text("That's today's word done")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("A new one arrives tomorrow. Premium plays as many as you like.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("See Premium") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.skyBlueText)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Said before they hit it rather than only after, so the limit is a known rule of the game
    /// instead of a surprise on the second tap.
    @ViewBuilder
    private var allowanceNote: some View {
        if !isPremium && !limitReached {
            Text("One word a day on Plus. Premium plays as many as you like.")
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func start() {
        isStarting = true
        errorMessage = nil
        Task {
            defer { isStarting = false }
            do {
                let session = try await BackendService.startWordGuessSession()
                route = session.sessionID
            } catch BackendError.wordGuessDailyLimit {
                // Not an error, and deliberately not shown as one: the allowance working is the
                // most ordinary thing that can happen here.
                limitReached = true
            } catch {
                errorMessage = "Couldn't start today's word. \(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack { WordGuessEntryView() }
        .environment(AppModel())
}
