//
//  ExportDataView.swift
//  Twofold
//
//  Taking a copy of a relationship that is still going.
//
//  `CoupleDataExporter` was written for the other case — an archive with a 90-day deadline on it —
//  and lived only in `ArchivedDataView`, behind `fetchArchivedCouples`, which filters
//  `status = 'dissolved'`. So the complete export was reachable only after a breakup, and a
//  currently-connected person on Plus or free could export nothing at all: their one option was
//  the Relationship Record, which is Premium and is a keepsake rather than a copy.
//
//  That is the wrong shape for a portability right, which does not care about anyone's
//  subscription tier or relationship status — and it is a strange thing for a couples app to say.
//  This is the same exporter, ungated, pointed at the couple you are in.
//
//  Choices here, where `ArchivedDataView` deliberately offers none: that screen is running against
//  a deletion date and should hand over everything without asking questions. This one is someone
//  deciding what they want, so it asks.
//
//  It offers no readable document, only the data. `CoupleDataExporter` can write the Relationship
//  Record as a PDF or a Word file, and offering that here handed every Plus subscriber the Premium
//  feature through a side door — the same document, produced by the same code, reached from a
//  screen with no tier check on it. Portability is about getting your data out in a form something
//  else can read; the Record is a keepsake, and it stays where it is priced.
//

import PostHog
import SwiftUI

struct ExportDataView: View {
    @Environment(AppModel.self) private var appModel

    /// `document: .none` and not offered — see this file's header. `ArchivedDataView` still gets
    /// the Record in its export, because that one is about not losing an archive before it expires
    /// rather than about handing over a keepsake.
    @State private var options = CoupleDataExporter.Options(document: .none)
    @State private var isExporting = false
    @State private var status = ""
    @State private var result: CoupleDataExporter.Result?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("What to include")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        Toggle("Trips", isOn: $options.trips)
                        Toggle("Memories", isOn: $options.memories)
                        // Indented under Memories because that is what they belong to, and switched
                        // off with them: photos without the rows naming them are a folder of
                        // filenames nobody can match to anything.
                        Toggle("Photos", isOn: $options.photos)
                            .padding(.leading, Theme.Spacing.md)
                            .disabled(!options.memories)
                            .opacity(options.memories ? 1 : 0.4)
                        Toggle("Flights", isOn: $options.flights)
                        Toggle("Games", isOn: $options.games)
                    }
                    .tint(Theme.skyBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Format")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)

                        Picker("Data", selection: $options.dataFormat) {
                            ForEach(CoupleDataExporter.Options.DataFormat.allCases) { format in
                                Text(format.label).tag(format)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(options.dataFormat == .csv
                             ? "Opens in Numbers, Excel or Google Sheets."
                             : "One file per table, for moving your data somewhere else.")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        if let result {
                            Text(result.summary)
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                                .fixedSize(horizontal: false, vertical: true)

                            ShareLink(
                                item: result.url,
                                preview: SharePreview("Twofold export", image: Image(systemName: "doc.zipper"))
                            ) {
                                Text("Save or share")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .background(Theme.primaryButtonGradient, in: Capsule())
                            .foregroundStyle(.white)

                            Button("Build it again") { self.result = nil }
                                .font(.subheadline)
                                .foregroundStyle(Theme.skyBlueText)
                                .frame(maxWidth: .infinity)
                        } else {
                            Button(action: runExport) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    if isExporting { ProgressView().controlSize(.small).tint(.white) }
                                    Text(isExporting ? status : "Export")
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                            .background(
                                (options.isEmpty || isExporting) ? AnyShapeStyle(Theme.subtleInk.opacity(0.3)) : AnyShapeStyle(Theme.primaryButtonGradient),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                            .disabled(options.isEmpty || isExporting)

                            if options.isEmpty {
                                Text("Pick at least one thing to export.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleInk)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage).font(.caption).foregroundStyle(Theme.heartRed)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Photos are downloaded as part of the export, so a large one can take a while and is best done on Wi-Fi.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Export your data")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: Export Data")
    }

    private func runExport() {
        guard let coupleID = appModel.backendCoupleID else {
            errorMessage = "Couldn't find your relationship. Try again in a moment."
            return
        }
        isExporting = true
        errorMessage = nil
        status = "Starting…"
        Task {
            do {
                result = try await CoupleDataExporter.export(
                    coupleID: coupleID,
                    partnerNames: [
                        appModel.currentUser.id: appModel.currentUser.name,
                        appModel.partner.id: appModel.partner.name,
                    ],
                    title: appModel.partner.name,
                    selfName: appModel.currentUser.name,
                    partnerName: appModel.partner.name,
                    options: options,
                    progress: { status = $0 }
                )
                Analytics.capture(Analytics.Event.dataExportGenerated, properties: [
                    "format": options.dataFormat.rawValue,
                    "photos": options.photos && options.memories,
                ])
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't build the export. Try again."
            }
            isExporting = false
        }
    }
}
