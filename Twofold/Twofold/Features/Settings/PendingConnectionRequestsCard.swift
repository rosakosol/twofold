//
//  PendingConnectionRequestsCard.swift
//  Twofold
//
//  Incoming "someone wants to connect" requests (double verification — redeeming a code no
//  longer connects instantly, see the invite-security migration's own header comment) awaiting
//  the inviter's decision. Shared by PartnerSetupView and PartnerRequiredGateView, the same two
//  pre-connection screens that already show PartnerConnectCard — self-hiding (renders nothing)
//  when there's nothing pending, so both call sites can drop it in unconditionally.
//

import SwiftUI

struct PendingConnectionRequestsCard: View {
    @Environment(AppModel.self) private var appModel
    /// The request being answered, on the same review screen Home opens.
    @State private var reviewing: BackendService.PendingConnectionRequest?

    var body: some View {
        Group {
            if !appModel.session.pendingConnectionRequests.isEmpty {
                SectionCard {
                    Text("Connection requests")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    ForEach(appModel.session.pendingConnectionRequests) { request in
                        requestRow(request)
                    }
                }
            }
        }
        // Outside the `if`: answering empties the list, and the sheet must not lose its host
        // while it is still closing.
        .sheet(item: $reviewing) { request in
            ConnectionRequestReviewView(request: request)
        }
    }

    /// One way to answer a request, wherever it is shown.
    ///
    /// This card used to carry its own Accept and Decline, and its Accept was not the same
    /// decision as the review screen's. The review screen looks for history with this person and
    /// asks "Bring it back, or start fresh?"; the card accepted at once with `restoreArchive:
    /// false`, so a returning couple who answered from Settings started fresh without being told
    /// their archive existed. It also had no Report or Block, and Decline asked nothing. The card
    /// now opens the review screen, which has all of that.
    private func requestRow(_ request: BackendService.PendingConnectionRequest) -> some View {
        let person = Person(
            id: request.requesterId,
            name: request.requesterFirstName,
            accentColor: Person.palette[0],
            avatarURL: request.requesterAvatarURL
        )
        return HStack(spacing: Theme.Spacing.sm) {
            AvatarView(person: person, size: 40)
            Text("\(request.requesterFirstName)")
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)

            // The same gradient capsule the full-screen accept uses, so it reads as the way into
            // that decision rather than a lesser control.
            Button("Review") { reviewing = request }
                .buttonStyle(.twofoldPrimaryCompact)
            .accessibilityLabel("Review \(request.requesterFirstName)'s request")
        }
    }
}

#Preview {
    PendingConnectionRequestsCard()
        .padding()
        .environment(AppModel())
}
