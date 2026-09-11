//
//  RelationshipRecordView.swift
//  Twofold
//
//  Everything the two of you have done, as a document you can keep.
//
//  The renderer is `CoupleHistoryPDFExporter`, which already existed and was already good — a cover
//  page and then one page per trip, memory and flight in one chronological run. It was only ever
//  reachable from `ArchivedDataView`, for a relationship that had ended and had ninety days before
//  its archive was deleted. That framing is why the thing it produced was a folder of CSVs: the
//  point there is survival, in formats anyone can open in ten years.
//
//  A couple who are still together want the opposite of an archive. So this offers the document
//  alone — see `CoupleDataExporter.relationshipRecordPDF` — and no spreadsheets.
//

import PostHog
import SwiftUI

struct RelationshipRecordView: View {
    @Environment(AppModel.self) private var appModel

    @State private var isBuilding = false
    @State private var status = ""
    @State private var recordURL: URL?
    @State private var errorMessage: String?
    /// Set when the couple has nothing to put in a record yet. Distinct from an error: nothing went
    /// wrong, there is simply no history, and telling someone their export failed when they have
    /// not been anywhere yet would be both wrong and a little bleak.
    @State private var isEmpty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Your Relationship Record")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)

                        Text("Every trip, memory and flight the two of you have shared, laid out in "
                            + "order as one document — with your photos. Yours to keep, print, or "
                            + "send to someone.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                            .fixedSize(horizontal: false, vertical: true)

                        if let recordURL {
                            ShareLink(
                                item: recordURL,
                                preview: SharePreview("Your Relationship Record", image: Image(systemName: "book.closed"))
                            ) {
                                Text("Save or share")
                                    .font(.subheadline.weight(.semibold))
                            }
                        } else {
                            Button(action: build) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    if isBuilding { ProgressView().controlSize(.small) }
                                    Text(isBuilding ? status : "Create your record")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .disabled(isBuilding)
                        }

                        if isEmpty {
                            Text("There's nothing to put in it yet. Add a trip, a memory or a "
                                + "flight and come back.")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Relationship Record")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Relationship Record")
    }

    private func build() {
        // `couple.id` rather than the private `backendCoupleID`: `performAdopt` assigns both from
        // the same `state.couple`, so they are the same value, and this one is reachable.
        let coupleID = appModel.couple.id
        isBuilding = true
        errorMessage = nil
        isEmpty = false
        status = "Starting…"
        Task {
            defer { isBuilding = false }
            let url = await CoupleDataExporter.relationshipRecordPDF(
                coupleID: coupleID,
                selfName: appModel.currentUser.name,
                partnerName: appModel.partner.name,
                selfPhotoURL: appModel.currentUser.avatarURL,
                partnerPhotoURL: appModel.partner.avatarURL,
                progress: { status = $0 }
            )
            // Nil covers both "nothing to include" and a render that failed. The first is by far
            // the likelier and is not a failure, so it is what gets said — a couple with no trips
            // yet should not be told their document broke.
            if let url {
                recordURL = url
            } else {
                isEmpty = true
            }
        }
    }
}
