//
//  ArchivedDataView.swift
//  Twofold
//
//  Read-only history of past partnerships — reachable only from Settings. Removing a partner
//  (see SettingsView) dissolves the couple rather than deleting it, so everything shared with
//  them lands here instead of vanishing outright.
//

import PostHog
import SwiftUI

struct ArchivedDataView: View {
    @State private var archivedCouples: [ArchivedCouple] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if archivedCouples.isEmpty {
                emptyState
            } else {
                List(archivedCouples) { couple in
                    NavigationLink {
                        ArchivedCoupleDetailView(couple: couple)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("With \(couple.partnerName)").font(.headline)
                            if let dissolvedAt = couple.dissolvedAt {
                                Text("Ended \(dissolvedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.subtleInk)
                            }
                        }
                        .padding(.vertical, 2)
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

    @Environment(\.dismiss) private var dismiss
    @State private var summary: ArchivedCoupleSummary?
    @State private var isLoading = true
    @State private var showingDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

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

                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Delete Permanently")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundStyle(.white)
                    .background(Theme.heartRed, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
                .disabled(isDeleting)

                Text("This can't be undone - trips, memories, flights, and game sessions with \(couple.partnerName) will be gone for good.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(couple.partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .alert("Delete this data permanently?", isPresented: $showingDeleteConfirm) {
            Button("Delete Permanently", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. All trips, memories, flights, and game sessions with \(couple.partnerName) will be permanently deleted.")
        }
        .postHogScreenView("Settings: Archived Couple Detail")
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
        isLoading = false
    }

    private func delete() async {
        isDeleting = true
        deleteError = nil
        do {
            try await BackendService.deleteDissolvedCoupleData(coupleID: couple.id)
            dismiss()
        } catch {
            deleteError = "Couldn't delete. Try again."
        }
        isDeleting = false
    }
}

#Preview {
    NavigationStack {
        ArchivedDataView()
    }
}
