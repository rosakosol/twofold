//
//  ArchivedDataView.swift
//  Twofold
//
//  Read-only history of past partnerships — reachable only from Settings. Removing a partner
//  (see SettingsView) dissolves the couple rather than deleting it, so everything shared with
//  them lands here instead of vanishing outright.
//
//  There is no delete button here, and that is the design rather than an omission. This screen
//  used to offer "Delete Permanently", which destroyed the shared archive for *both* people on one
//  person's say-so — and almost everyone reaching for it wanted an old relationship out of their
//  own sight, not out of someone else's account.
//
//  So the two wishes are separated and neither is that button. Hiding takes it off your list,
//  alone, instantly, destroying nothing. Deleting happens on its own 90 days after the
//  relationship ended, to both copies, with nobody able to bring it forward — see migration
//  20261005000000. What is left to do here is keep a copy, which is what the export is for.
//

import PostHog
import SwiftUI

struct ArchivedDataView: View {
    @State private var archivedCouples: [ArchivedCouple] = []
    @State private var isLoading = true
    /// Hidden archives are still here and still readable — this is what makes hiding reversible,
    /// and the difference between hiding and deleting worth having.
    @State private var showingHidden = false

    private var visibleCouples: [ArchivedCouple] {
        showingHidden ? archivedCouples : archivedCouples.filter { !$0.isHidden }
    }

    private var hiddenCount: Int { archivedCouples.filter(\.isHidden).count }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleCouples.isEmpty && hiddenCount == 0 {
                emptyState
            } else {
                List {
                    ForEach(visibleCouples) { couple in
                        NavigationLink {
                            ArchivedCoupleDetailView(couple: couple, onChange: { Task { await load() } })
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text("With \(couple.partnerName)").font(.headline)
                                    if couple.isHidden {
                                        Image(systemName: "eye.slash")
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                }
                                if let dissolvedAt = couple.dissolvedAt {
                                    Text("Ended \(dissolvedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(Theme.subtleInk)
                                }
                                // On the list, not just the detail screen. This is a deadline
                                // nobody chose and nobody can stop, so it should not take a tap
                                // to find out about.
                                if let notice = couple.deletionNotice {
                                    Text(notice)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(couple.deletionIsImminent ? Theme.heartRed : Theme.subtleInk)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if hiddenCount > 0 {
                        Button(showingHidden ? "Hide hidden archives" : "Show \(hiddenCount) hidden") {
                            showingHidden.toggle()
                        }
                        .font(.caption)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Archived Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .postHogScreenView("Settings: Archived Data")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "archivebox")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text("No archived data").font(.headline)
            Text("If you ever remove a partner, everything you shared with them will show up here.")
                .font(.caption)
                .foregroundStyle(Theme.subtleInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        archivedCouples = (try? await BackendService.fetchArchivedCouples()) ?? []
        isLoading = false
    }
}

struct ArchivedCoupleDetailView: View {
    let couple: ArchivedCouple
    @Environment(AppModel.self) private var appModel
    /// Lets the list reload after a hide or a purge, so it never shows something that has changed
    /// underneath it.
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var summary: ArchivedCoupleSummary?
    @State private var isLoading = true
    @State private var hideError: String?
    @State private var isHidden = false
    @State private var isExporting = false
    @State private var exportStatus = ""
    @State private var exportResult: CoupleDataExporter.Result?
    @State private var exportError: String?
    /// Off by default, and Premium-only. The archive export used to include the Relationship
    /// Record unconditionally, which handed every Plus subscriber the Premium document the moment
    /// a relationship ended — the same side door the data export had, opened by a breakup instead
    /// of a tap. The data itself stays free; the keepsake is the thing being sold.
    @State private var includeRecord = false
    @State private var showingPaywall = false
    /// Bought-and-unspent single exports. This screen has to honour them, and not only for
    /// consistency: `RelationshipTimelineView` is behind `partnerConnected`, so once a
    /// relationship has ended the archive is the *only* place a Record can be had at all. Refusing
    /// a purchased export here would make it unbuyable exactly when someone wants it most — a
    /// keepsake of something that ended, on a 90-day clock.
    @State private var credits: Int?
    @State private var isBuyingRecord = false
    @State private var subscriptionStore = SubscriptionStore()
    @State private var purchaseError: String?

    /// Premium exports without limit; everyone else needs a credit in hand.
    private var canIncludeRecord: Bool {
        !appModel.isPremiumLocked || (credits ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("With \(couple.partnerName)").font(.title3.weight(.bold))
                    if let startedDatingOn = couple.startedDatingOn {
                        Text("Together since \(startedDatingOn.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    if let dissolvedAt = couple.dissolvedAt {
                        Text("Ended \(dissolvedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }

                if let purgeDate = couple.scheduledPurgeAt {
                    SectionCard {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .foregroundStyle(couple.deletionIsImminent ? Theme.heartRed : Theme.skyBlue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(couple.deletionNotice ?? "")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Text("Archived history is kept for 90 days. On \(purgeDate.formatted(date: .abbreviated, time: .omitted)) everything here is permanently deleted for both of you.")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let summary {
                    SectionCard {
                        Text("Archived data").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        summaryRow("Trips", summary.tripCount)
                        summaryRow("Memories", summary.memoryCount)
                        summaryRow("Flights", summary.flightCount)
                        summaryRow("Game sessions", summary.gameSessionCount)
                    }
                }

                if let hideError {
                    Text(hideError).font(.caption).foregroundStyle(Theme.heartRed)
                }

                // Offered first, and as the ordinary-weight action, because it is what most people
                // actually want: this out of my sight. It is instant, needs nobody's agreement,
                // and takes nothing away from either of them.
                SectionCard {
                    Button(isHidden ? "Show in my archive" : "Hide from my archive") {
                        Task { await setHidden(!isHidden) }
                    }
                    .font(.subheadline.weight(.semibold))
                    Text(isHidden
                         ? "Hidden from your list. \(couple.partnerName) still has their copy, and so do you."
                         : "Takes it off your list without deleting anything. Only affects what you see.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                exportSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(couple.partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            // Only for people who pay per export — Premium has no balance to report.
            guard appModel.isPremiumLocked else { return }
            credits = (try? await BackendService.recordExportCreditCount()) ?? 0
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView() }
        }
        .postHogScreenView("Settings: Archived Couple Detail")
    }

    /// Getting a copy out before the deadline.
    ///
    /// Above the delete section deliberately. Both of the things below this lead towards losing the
    /// archive — one on a timer nobody can stop — and someone should be offered a way to keep it
    /// before they are offered ways to lose it.
    @ViewBuilder
    private var exportSection: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Export everything")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                if let exportResult {
                    Text(exportResult.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)

                    ShareLink(
                        item: exportResult.url,
                        preview: SharePreview("Twofold export", image: Image(systemName: "doc.zipper"))
                    ) {
                        Text("Save or share")
                            .font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("Trips, memories and their photos, flights and games — as spreadsheets and image files. Yours to keep whatever happens to the archive.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .fixedSize(horizontal: false, vertical: true)

                    // Shown and disabled rather than hidden for someone on Plus, the same way the
                    // Relationship Record screen handles its own export: a control that is not
                    // there explains nothing.
                    Toggle(isOn: $includeRecord) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include your Relationship Record")
                                .font(.subheadline)
                            Text(appModel.isPremiumLocked
                                 ? "A PDF of your story together. Premium only — the data above is free either way."
                                 : "A PDF of your story together, alongside the data.")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }
                    .tint(Theme.skyBlue)
                    .disabled(!canIncludeRecord)

                    if appModel.isPremiumLocked && (credits ?? 0) == 0 {
                        Button { buyOneRecordExport() } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                if isBuyingRecord { ProgressView().controlSize(.small) }
                                Text(isBuyingRecord ? "Just a moment…" : "Buy this export")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .foregroundStyle(Theme.skyBlueText)
                        .disabled(isBuyingRecord)

                        Button("Or see Premium, for unlimited exports") { showingPaywall = true }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.subtleInk)
                            .disabled(isBuyingRecord)
                    }

                    if let purchaseError {
                        Text(purchaseError).font(.caption).foregroundStyle(Theme.heartRed)
                    }

                    Button(action: runExport) {
                        HStack(spacing: Theme.Spacing.xs) {
                            if isExporting { ProgressView().controlSize(.small) }
                            Text(isExporting ? exportStatus : "Export everything")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .disabled(isExporting)
                }

                if let exportError {
                    Text(exportError).font(.caption).foregroundStyle(Theme.heartRed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The purchase only opens the till. The credit is written by the RevenueCat webhook against
    /// the store's transaction id, so this polls for it rather than assuming.
    private func buyOneRecordExport() {
        isBuyingRecord = true
        purchaseError = nil
        Task {
            do {
                let bought = try await subscriptionStore.purchaseConsumable(
                    RevenueCatConfig.ProductIdentifier.recordExport
                )
                if bought {
                    let deadline = Date.now.addingTimeInterval(15)
                    while Date.now < deadline {
                        if let count = try? await BackendService.recordExportCreditCount(), count > 0 {
                            credits = count
                            includeRecord = true
                            break
                        }
                        try? await Task.sleep(for: .milliseconds(750))
                    }
                    if (credits ?? 0) == 0 {
                        purchaseError = "Your purchase went through, but it's taking a moment to arrive. Come back shortly."
                    }
                }
            } catch {
                purchaseError = (error as? LocalizedError)?.errorDescription
                    ?? "That didn't go through. Try again in a moment."
            }
            isBuyingRecord = false
        }
    }

    private func runExport() {
        isExporting = true
        exportError = nil
        exportStatus = "Starting…"
        Task {
            do {
                exportResult = try await CoupleDataExporter.export(
                    coupleID: couple.id,
                    partnerNames: [
                        appModel.currentUser.id: appModel.currentUser.name,
                        appModel.partner.id: couple.partnerName,
                    ],
                    title: couple.partnerName,
                    selfName: appModel.currentUser.name,
                    partnerName: couple.partnerName,
                    // Belt and braces: the toggle is disabled for Plus, but the value it carries
                    // is the one that reaches the exporter, so the tier is checked here too.
                    options: CoupleDataExporter.Options(
                        document: (includeRecord && canIncludeRecord) ? .pdf : .none
                    ),
                    progress: { exportStatus = $0 }
                )
                // Charged after the zip exists, never before — and only when the Record was
                // actually included. A failed export must not take somebody's purchase.
                if includeRecord && appModel.isPremiumLocked {
                    if (try? await BackendService.spendRecordExportCredit()) == true {
                        credits = max((credits ?? 1) - 1, 0)
                    }
                }
            } catch {
                exportError = (error as? LocalizedError)?.errorDescription ?? "Couldn't build the export. Try again."
            }
            isExporting = false
        }
    }

    private func summaryRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.subtleInk)
            Spacer()
            Text("\(count)").foregroundStyle(Theme.ink)
        }
    }

    private func load() async {
        summary = try? await BackendService.fetchArchivedCoupleSummary(coupleID: couple.id)
        isHidden = (try? await BackendService.coupleArchiveState(coupleID: couple.id))?.hidden ?? couple.isHidden
        isLoading = false
    }

    private func setHidden(_ hidden: Bool) async {
        hideError = nil
        do {
            try await BackendService.setCoupleArchiveHidden(coupleID: couple.id, hidden: hidden)
            isHidden = hidden
            onChange()
        } catch {
            hideError = "Couldn't update that. Try again."
        }
    }

}

#Preview {
    NavigationStack {
        ArchivedDataView()
    }
}
