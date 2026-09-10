//
//  ArchivedDataView.swift
//  Twofold
//
//  Read-only history of past partnerships — reachable only from Settings. Removing a partner
//  (see SettingsView) dissolves the couple rather than deleting it, so everything shared with
//  them lands here instead of vanishing outright.
//
//  Two actions, deliberately separated. This screen used to offer one — "Delete Permanently" —
//  which destroyed the shared archive for *both* people on one person's say-so. Almost everyone
//  reaching for that button wants an old relationship out of their sight, and was instead reaching
//  into someone else's account. So hiding is now its own thing: unilateral, instant, and
//  destructive of nothing. Deleting is still available, and now takes both partners agreeing (see
//  migration 20261003000000).
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

/// Which of four states the delete half of the archive screen is in.
///
/// Pulled out of the view so it can be tested. The thing worth pinning is not the wording but the
/// pairing: `deletesImmediately` decides whether the confirmation says "this can't be undone", and
/// saying that for a tap that only sends a request would teach people to skip the words on the one
/// screen where they matter. Two of the four states destroy nothing.
enum ArchivePurgeStage: Equatable {
    /// Nobody has asked yet.
    case nobodyAsked
    /// This person has asked and is waiting on their partner.
    case awaitingPartner
    /// The partner has asked. Agreeing is what destroys it.
    case partnerAsked
    /// The partner deleted their account, so there is nobody left to ask.
    case soleOwner

    static func resolve(_ state: BackendService.CoupleArchiveState?) -> ArchivePurgeStage {
        guard let state else { return .nobodyAsked }
        // Checked before the request states: with the partner gone, what they did or didn't ask
        // for before leaving no longer decides anything.
        if !state.partnerExists { return .soleOwner }
        if state.partnerIsWaitingOnMe { return .partnerAsked }
        if state.iRequestedPurge { return .awaitingPartner }
        return .nobodyAsked
    }

    /// Whether the destructive button destroys something on this tap.
    var deletesImmediately: Bool {
        switch self {
        case .soleOwner, .partnerAsked: true
        case .nobodyAsked, .awaitingPartner: false
        }
    }
}

struct ArchivedCoupleDetailView: View {
    let couple: ArchivedCouple
    /// Lets the list reload after a hide or a purge, so it never shows something that has changed
    /// underneath it.
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var summary: ArchivedCoupleSummary?
    @State private var isLoading = true
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var state: BackendService.CoupleArchiveState?
    @State private var isHidden = false

    private var stage: ArchivePurgeStage { .resolve(state) }

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

                if let deleteError {
                    Text(deleteError).font(.caption).foregroundStyle(Theme.heartRed)
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

                deleteSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(couple.partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert(confirmTitle, isPresented: $showingDeleteConfirm) {
            Button(confirmAction, role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .postHogScreenView("Settings: Archived Couple Detail")
    }

    /// The destructive half. Four states, and which one is showing is the entire point of the
    /// screen — this used to be a single button that destroyed both people's copy on one tap.
    @ViewBuilder
    private var deleteSection: some View {
        SectionCard {
            if stage == .soleOwner {
                // Nobody left to ask. Without this the archive would be undeletable forever by
                // the only person who can still see it.
                destructiveButton("Delete Permanently")
                Text("\(couple.partnerName) has deleted their account, so this is yours alone to delete.")
                    .font(.caption).foregroundStyle(Theme.subtleInk).fixedSize(horizontal: false, vertical: true)
            } else if stage == .partnerAsked {
                destructiveButton("Delete for both of us")
                Text("\(couple.partnerName) has asked to delete everything you shared. If you agree, it's deleted for both of you and can't be undone.")
                    .font(.caption).foregroundStyle(Theme.subtleInk).fixedSize(horizontal: false, vertical: true)
            } else if stage == .awaitingPartner {
                Text("Waiting for \(couple.partnerName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("You've asked to delete everything you shared. It stays until \(couple.partnerName) agrees too.")
                    .font(.caption).foregroundStyle(Theme.subtleInk).fixedSize(horizontal: false, vertical: true)
                Button("Cancel my request") {
                    Task { await withdraw() }
                }
                .font(.caption.weight(.semibold))
            } else {
                destructiveButton("Ask to delete permanently")
                Text("This is \(couple.partnerName)'s history too, so deleting it takes both of you. They'll be asked to agree before anything is removed.")
                    .font(.caption).foregroundStyle(Theme.subtleInk).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func destructiveButton(_ title: String) -> some View {
        Button(role: .destructive) {
            showingDeleteConfirm = true
        } label: {
            HStack {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .foregroundStyle(.white)
            .background(Theme.heartRed, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .disabled(isDeleting)
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
        state = try? await BackendService.coupleArchiveState(coupleID: couple.id)
        isHidden = state?.hidden ?? couple.isHidden
        isLoading = false
    }

    private func setHidden(_ hidden: Bool) async {
        deleteError = nil
        do {
            try await BackendService.setCoupleArchiveHidden(coupleID: couple.id, hidden: hidden)
            isHidden = hidden
            onChange()
        } catch {
            deleteError = "Couldn't update that. Try again."
        }
    }

    private func withdraw() async {
        deleteError = nil
        do {
            try await BackendService.withdrawCouplePurge(coupleID: couple.id)
            await load()
            onChange()
        } catch {
            deleteError = "Couldn't cancel that. Try again."
        }
    }

    /// Asks, and only deletes if that completes the pair. The screen must not claim a deletion
    /// that hasn't happened, so the two outcomes are handled separately rather than both being
    /// treated as success.
    private func delete() async {
        isDeleting = true
        deleteError = nil
        do {
            let outcome = try await BackendService.requestCouplePurge(coupleID: couple.id)
            onChange()
            switch outcome {
            case .purged:
                dismiss()
            case .awaitingPartner:
                await load()
            }
        } catch {
            deleteError = "Couldn't do that. Try again."
        }
        isDeleting = false
    }
}

private extension ArchivedCoupleDetailView {
    /// The confirmation has to match what the tap actually does — see `ArchivePurgeStage`.
    var confirmTitle: String {
        stage.deletesImmediately ? "Delete this data permanently?" : "Ask \(couple.partnerName) to delete this?"
    }

    var confirmAction: String { stage.deletesImmediately ? "Delete Permanently" : "Send Request" }

    var confirmMessage: String {
        stage.deletesImmediately
            ? "This can't be undone. All trips, memories, flights, and game sessions with \(couple.partnerName) will be permanently deleted."
            : "Nothing is deleted yet. \(couple.partnerName) will be asked to agree, and everything stays until they do."
    }
}

#Preview {
    NavigationStack {
        ArchivedDataView()
    }
}
