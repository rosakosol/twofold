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

//  A note on the blue, since it is easy to "fix" this in a way that makes it worse:
//
//  White on Twofold's blues does not reach WCAG AA at normal text size anywhere in the app.
//  Measured against white: `skyBlue` is 2.60:1 in light and 1.70:1 in dark, `primaryButtonGradient`
//  runs 1.99 -> 3.52 in light and 2.60 -> 3.52 in dark. Only the foot of the gradient clears
//  AA-large (3.0).
//
//  `Theme.skyBlueText` (#1F6F9E) measures 5.49:1 and would clear AA outright, but it is a much
//  deeper blue than the brand's buttons, so using it here alone would make this one control look
//  wrong. Deepening `primaryButtonGradient`'s stops would fix every white-on-blue button at once
//  and is the change worth making deliberately, rather than one screen at a time.

struct PendingConnectionRequestsCard: View {
    @Environment(AppModel.self) private var appModel
    @State private var respondingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        if !appModel.pendingConnectionRequests.isEmpty {
            SectionCard {
                Text("Connection requests")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.subtleInk)

                ForEach(appModel.pendingConnectionRequests) { request in
                    requestRow(request)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.heartRed)
                }
            }
        }
    }

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
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)

            if respondingID == request.id {
                ProgressView()
            } else {
                Button("Decline") { respond(request, accept: false) }
                    .buttonStyle(.bordered)
                    .tint(Theme.subtleInk)

                // The same gradient capsule the full-screen accept uses
                // (`ConnectionRequestReviewView`), rather than `.borderedProminent` tinted with a
                // flat `skyBlue`. Two reasons, and the second is the one that mattered.
                //
                // It matches: this is the same decision as that screen's, and it read as a
                // different, lesser control.
                //
                // And it is more legible. White on flat `skyBlue` measures 2.60:1 in light mode
                // and — because `skyBlue` is *lighter* in dark mode, not darker — 1.70:1 in dark,
                // which is close to unreadable. The gradient runs to `#3D8FC9` at its foot, 3.52:1,
                // so the text sits on the darkest part of it. See the note below: that is a real
                // improvement and still short of AA for normal-size text.
                Button { respond(request, accept: true) } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, 8)
                        .background(Theme.primaryButtonGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func respond(_ request: BackendService.PendingConnectionRequest, accept: Bool) {
        respondingID = request.id
        errorMessage = nil
        Task {
            errorMessage = await appModel.respondToConnectionRequest(request, accept: accept)
            respondingID = nil
        }
    }
}

#Preview {
    PendingConnectionRequestsCard()
        .padding()
        .environment(AppModel())
}
