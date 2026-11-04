//
//  LoadingGate.swift
//  Twofold
//
//  Holding a screen back until the pieces it is made of are ready, so it appears once, whole,
//  rather than assembling itself in front of the person looking at it.
//
//    LoadingGate.wait   waits for some work, or for a timeout, whichever comes first
//    LoadingGateView    a delayed spinner until it is ready, then the content faded in as one
//
//  The timeout is the point. One slow piece — a photo over a bad connection, map tiles with no
//  network at all — must never hold the rest of a screen hostage, so after it the content shows
//  anyway with that piece drawing its own placeholder, and the work carries on behind it.
//

import SwiftUI

enum LoadingGate {
    enum Outcome: Equatable {
        /// The work finished inside the timeout.
        case ready
        /// The timeout passed first. The work has not been cancelled and is still running.
        case timedOut
    }

    /// Runs `work` and returns once it finishes or `timeout` passes, whichever is first.
    ///
    /// The work is not cancelled on a timeout, and not cancelled if the caller is: what it fetches
    /// is going into a cache the screen is about to read from anyway, so stopping it would only
    /// mean starting the same download again a moment later.
    static func wait(upTo timeout: Duration, for work: @escaping () async -> Void) async -> Outcome {
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            let timer = Task {
                try? await Task.sleep(for: timeout)
                race.finish(.timedOut)
            }
            Task {
                await work()
                race.finish(.ready)
                timer.cancel()
            }
        }
    }

    /// Whichever side finishes first resumes the caller; the other finds nothing left to resume.
    /// Main-actor isolated, as everything in this target is by default, so the two never interleave.
    private final class Race {
        var continuation: CheckedContinuation<Outcome, Never>?

        func finish(_ outcome: Outcome) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }
}

/// A spinner until `isReady`, then the content, faded in as one piece.
///
/// The spinner waits a beat before it shows. Most loads finish from cache well inside that, and a
/// spinner that flickers on and straight off again is more distracting than the short blank it
/// replaces.
struct LoadingGateView<Content: View>: View {
    let isReady: Bool
    @ViewBuilder var content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinnerVisible = false

    /// How long the blank lasts before the spinner appears.
    static var spinnerDelay: Duration { .milliseconds(250) }

    var body: some View {
        ZStack {
            if isReady {
                content
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(spinnerVisible ? 1 : 0)
                    .task {
                        try? await Task.sleep(for: Self.spinnerDelay)
                        withAnimation(.easeIn(duration: 0.2)) { spinnerVisible = true }
                    }
                    .transition(.opacity)
            }
        }
        // A crossfade rather than anything that moves, so it stays under Reduce Motion — just
        // quicker, so it reads as a cut softened rather than an effect.
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.3), value: isReady)
    }
}

#Preview {
    @Previewable @State var isReady = false
    LoadingGateView(isReady: isReady) {
        Text("Everything at once")
    }
    .task {
        try? await Task.sleep(for: .seconds(2))
        isReady = true
    }
    .background(ScreenBackground())
}
