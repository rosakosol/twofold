//
//  AddContentGate.swift
//  Twofold
//
//  Turns "adding needs a subscription" into a paywall somebody can act on, rather than a write that
//  fails without saying why.
//
//  Since 20261028000000 the rule lives in RLS: reading and deleting are open to everyone, adding
//  and editing need a subscription. That is the right place for it — the only place that cannot be
//  bypassed — but a policy refusal reaches the app as a generic error. A lapsed couple tapping
//  "Add memory" would have filled in a whole screen and then been told "something went wrong",
//  which is worse than the paywall this replaced: at least a paywall explained itself.
//
//  Applied at the *sheet* rather than at each button. Nine separate places set `showingAddTrip`,
//  `showingAddFlight` or `showingAddMemory` — a checklist row, a toolbar, an empty state, a menu —
//  and a check written nine times is a check somebody adds a tenth caller without. They all funnel
//  into three sheets, so the decision is made once where the content would actually be created.
//
//  `AppModel.canAddContent` mirrors the policy. If the two ever disagree the database wins, which
//  is the right way round: the worst this can do is offer a purchase to somebody who did not need
//  one, where the worst the other way round is a silent failure.
//

import SwiftUI

extension View {
    /// Presents `content` when the couple may add to their story, and the paywall when they may
    /// not — so the same button works for everyone and explains itself to the people it stops.
    func addContentSheet<C: View>(
        isPresented: Binding<Bool>,
        canAdd: Bool,
        @ViewBuilder content: @escaping () -> C
    ) -> some View {
        sheet(isPresented: isPresented) {
            if canAdd {
                content()
            } else {
                NavigationStack { PaywallView() }
            }
        }
    }
}
