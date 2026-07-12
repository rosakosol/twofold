//
//  NotificationPreferencesView.swift
//  Twofold
//
//  Global "notify me when my partner..." toggles — separate from FlightTrackingView's own
//  per-flight notification toggles, which stay scoped to each individual tracked flight.
//

import SwiftUI

struct NotificationPreferencesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var partnerDrawingSaved = true
    @State private var partnerTripAdded = true
    @State private var partnerMemoryAdded = true
    @State private var partnerGameStarted = true
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("Notify me when \(appModel.partner.name)…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Toggle("Saves a drawing", isOn: $partnerDrawingSaved).font(.subheadline)
                    Toggle("Adds a trip", isOn: $partnerTripAdded).font(.subheadline)
                    Toggle("Adds a memory", isOn: $partnerMemoryAdded).font(.subheadline)
                    Toggle("Starts a game", isOn: $partnerGameStarted).font(.subheadline)
                }

                Text("Flight updates have their own notification settings on each tracked flight.")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onChange(of: partnerDrawingSaved) { _, _ in saveIfLoaded() }
        .onChange(of: partnerTripAdded) { _, _ in saveIfLoaded() }
        .onChange(of: partnerMemoryAdded) { _, _ in saveIfLoaded() }
        .onChange(of: partnerGameStarted) { _, _ in saveIfLoaded() }
    }

    private func load() async {
        if let prefs = try? await BackendService.fetchCoupleNotificationPreferences() {
            partnerDrawingSaved = prefs.partnerDrawingSaved
            partnerTripAdded = prefs.partnerTripAdded
            partnerMemoryAdded = prefs.partnerMemoryAdded
            partnerGameStarted = prefs.partnerGameStarted
        }
        isLoaded = true
    }

    /// Individually-bound toggles saved as one upsert on change, same pattern as
    /// FlightTrackingView's per-flight notification toggles — guarded by `isLoaded` so the
    /// initial fetch populating these `@State` vars doesn't itself trigger a redundant save.
    private func saveIfLoaded() {
        guard isLoaded else { return }
        let prefs = BackendService.CoupleNotificationPreferences(
            partnerDrawingSaved: partnerDrawingSaved,
            partnerTripAdded: partnerTripAdded,
            partnerMemoryAdded: partnerMemoryAdded,
            partnerGameStarted: partnerGameStarted
        )
        Task { try? await BackendService.upsertCoupleNotificationPreferences(prefs) }
    }
}

#Preview {
    NavigationStack {
        NotificationPreferencesView()
    }
    .environment(AppModel())
}
