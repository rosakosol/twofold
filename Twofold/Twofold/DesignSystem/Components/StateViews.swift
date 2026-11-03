//
//  StateViews.swift
//  Twofold
//
//  The two things a screen shows instead of its content: nothing to show yet, and something that
//  went wrong.
//
//  These were four or more patterns: `GameErrorState` on the game screens (with a Try again bolted
//  on in two places and missing everywhere else), `ContentUnavailableView` on one screen, and an
//  icon, headline and caption stack hand-rolled on a dozen more, each with its own font, colour and
//  padding. Some screens had no error state at all and showed an empty one instead, which tells
//  somebody whose network dropped that their data is gone (UX-3).
//
//    EmptyStateView   an icon, a title, a line of explanation, and optionally an action
//    ErrorStateView   the same shape for a failure, with Try again when there is a way to retry
//
//  Loading stays a plain `ProgressView`.
//

import SwiftUI

/// Nothing to show yet: "No archived data", "No one blocked", "No games yet".
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var actions: Actions

    var body: some View {
        StateLayout(systemImage: systemImage, iconColor: Theme.textSecondary, title: Text(title), message: message.map { Text($0) }) {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

/// Something went wrong. With `retry`, a Try again button that shows a spinner while the retry
/// runs; without one, just the explanation.
struct ErrorStateView: View {
    var title: LocalizedStringKey?
    private let message: Text
    var retry: (() async -> Void)?

    @State private var isRetrying = false

    /// A message written here, looked up in the String Catalog like any other literal.
    init(title: LocalizedStringKey? = nil, message: LocalizedStringKey, retry: (() async -> Void)? = nil) {
        self.title = title
        self.message = Text(message)
        self.retry = retry
    }

    /// A message already worded at run time — from an error, through `message(for:)` or
    /// `BackendFailure` — which has been localized where it was made, so it is shown as it is.
    ///
    /// Its own label, not an overload of `message:`. With both taking a string, a literal picks
    /// the `String` one, and the literal then skips the catalog: "Check your connection and try
    /// again." reached every language in English.
    init(title: LocalizedStringKey? = nil, verbatim message: String, retry: (() async -> Void)? = nil) {
        self.title = title
        self.message = Text(verbatim: message)
        self.retry = retry
    }

    /// The same, worded from the error itself (see `ErrorStateView.message(for:)`).
    init(title: LocalizedStringKey? = nil, error: Error, retry: (() async -> Void)? = nil) {
        self.init(title: title, verbatim: Self.message(for: error), retry: retry)
    }

    var body: some View {
        StateLayout(
            systemImage: "exclamationmark.triangle.fill",
            iconColor: Theme.error,
            title: title.map { Text($0) },
            message: message
        ) {
            if let retry {
                Button {
                    isRetrying = true
                    Task {
                        await retry()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying { ProgressView() } else { Text("Try again") }
                }
                .buttonStyle(.twofoldPrimaryCompact)
                .disabled(isRetrying)
            }
        }
    }

    /// What to say about a failed load.
    ///
    /// No connection gets its own plain sentence rather than `URLError`'s "The Internet connection
    /// appears to be offline.", and a server that couldn't be reached gets one that says what to
    /// do. Anything else goes through `BackendFailure`, which names the refusals the app knows.
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return String(localized: "You're offline. Check your connection and try again.")
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .secureConnectionFailed:
                return String(localized: "Couldn't reach Twofold. Check your connection and try again.")
            default:
                break
            }
        }
        return BackendFailure.message(for: error)
    }
}

/// The layout both share: an icon, an optional headline, an optional explanation and whatever
/// actions sit under them, centred in the space they are given.
private struct StateLayout<Actions: View>: View {
    let systemImage: String
    let iconColor: Color
    let title: Text?
    let message: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(iconColor)
                .accessibilityHidden(true)
            if let title {
                title
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
            }
            if let message {
                message
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty") {
    EmptyStateView(
        systemImage: "archivebox",
        title: "No archived data",
        message: "If you ever remove a partner, everything you shared with them will show up here."
    )
}

#Preview("Error") {
    ErrorStateView(error: URLError(.notConnectedToInternet)) {}
}
