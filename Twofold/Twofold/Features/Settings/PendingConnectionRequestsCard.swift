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
            avatarURL: request.requesterAvatarPath.flatMap { BackendService.avatarPublicURL(path: $0) }
        )
        return HStack(spacing: Theme.Spacing.sm) {
            AvatarView(person: person, size: 40)
            Text(request.requesterFirstName)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)

            if respondingID == request.id {
                ProgressView()
            } else {
                Button("Decline") { respond(request, accept: false) }
                    .buttonStyle(.bordered)
                    .tint(Theme.subtleInk)
                Button("Accept") { respond(request, accept: true) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.skyBlue)
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
