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
    @State private var respondingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        if !appModel.pendingConnectionRequests.isEmpty {
            SectionCard {
                Text("Connection requests")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)

                ForEach(appModel.pendingConnectionRequests) { request in
                    requestRow(request)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.error)
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
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)

            if respondingID == request.id {
                ProgressView()
            } else {
                Button("Decline") { respond(request, accept: false) }
                    .buttonStyle(.bordered)
                    .tint(Theme.textSecondary)

                // The same gradient capsule the full-screen accept uses
                // (`ConnectionRequestReviewView`), rather than `.borderedProminent` tinted with a
                // flat accent, so it reads as the same decision rather than a lesser control. The
                // label is `onPrimaryButton`, which clears AA on the gradient in both appearances.
                Button { respond(request, accept: true) } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onPrimaryButton)
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
