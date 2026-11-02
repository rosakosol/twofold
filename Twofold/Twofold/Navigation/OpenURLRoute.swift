//
//  OpenURLRoute.swift
//  Twofold
//
//  What a link opened into the app should do, given where the app is when it can act on it.
//
//  Split out of `RootView.consumePendingOpenURL` so the decision can be tested without a view.
//

import Foundation

enum OpenURLRoute: Equatable {
    /// The session is still loading. Keep the link and ask again once it has.
    case wait
    /// Nothing here for this link.
    case ignore
    /// Somebody with an account tapped an invite: the redeem sheet, over whatever is showing.
    case redeemInvite(code: String)
    /// Somebody with no account tapped an invite: onboarding's invitee flow.
    case startInvite(code: String)
    /// A password-reset email, for onboarding to exchange for a session.
    case passwordRecovery(URL)
    /// A widget's link into the app.
    case widget(WidgetDeepLink.Destination)

    /// One decision for every link, whichever screen is up.
    ///
    /// There used to be two handlers: this view's, for people in the app, and onboarding's own
    /// `.onOpenURL` for everyone else. A link that launched the app cold arrived while neither the
    /// app nor onboarding was on screen — only the loading spinner — so RootView held it, and when
    /// loading finished it dropped it for anybody not in the app, on the comment that onboarding's
    /// handler would deal with it. That handler had never seen it. An invitee who installed the
    /// app and then tapped the link in Messages, and anybody opening a password-reset email with
    /// the app closed, landed on Welcome with nothing.
    ///
    /// An invite is decided by whether an account exists, not by which screen is showing.
    /// Onboarding's handler sent a signed-in person who had not finished onboarding to "Create
    /// account", which makes a second account and orphans the first (ONB-2). Anyone signed in gets
    /// the redeem sheet instead, as the app's own users always did.
    static func route(for url: URL, isLoadingSession: Bool, hasCouple: Bool, isSignedIn: Bool) -> OpenURLRoute {
        guard !isLoadingSession else { return .wait }
        if let code = InviteCode.code(from: url) {
            return isSignedIn ? .redeemInvite(code: code) : .startInvite(code: code)
        }
        guard hasCouple else {
            return OnboardingCoordinatorView.isPasswordRecoveryLink(url) ? .passwordRecovery(url) : .ignore
        }
        guard let destination = WidgetDeepLink.destination(for: url) else { return .ignore }
        return .widget(destination)
    }
}
