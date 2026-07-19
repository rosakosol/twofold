//
//  NotificationPreferencesView.swift
//  Twofold
//
//  Global "notify me when my partner..." toggles — separate from FlightTrackingView's own
//  per-flight notification toggles, which stay scoped to each individual tracked flight.
//

import PostHog
import SwiftUI

struct NotificationPreferencesView: View {
    @Environment(AppModel.self) private var appModel

    @State private var partnerDrawingSaved = true
    @State private var partnerTripAdded = true
    @State private var partnerMemoryAdded = true
    @State private var partnerGameStarted = true
    @State private var partnerGameResultsReady = true
    @State private var partnerGamePartnerFinished = true
    @State private var dailyStreakReminder = true
    @State private var partnerInviteReminder = true
    @State private var isLoaded = false
    @State private var loadFailed = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if loadFailed {
                    SectionCard {
                        Text("Couldn't load your notification settings.").font(.subheadline)
                        Button("Retry") { Task { await load() } }
                    }
                }

                // Only meaningful pre-pairing — once `appModel.partner` is real, there's nothing
                // left to be reminded to invite.
                if !appModel.partnerConnected {
                    SectionCard {
                        Toggle("Reminders to invite my partner", isOn: $partnerInviteReminder).font(.subheadline)
                        Text("A couple of nudges in your first few days if you haven't connected yet.")
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }

                SectionCard {
                    Text("Notify me when \(appModel.partner.name)…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    Toggle("Saves a drawing", isOn: $partnerDrawingSaved).font(.subheadline)
                    Toggle("Adds a trip", isOn: $partnerTripAdded).font(.subheadline)
                    Toggle("Adds a memory", isOn: $partnerMemoryAdded).font(.subheadline)
                    Toggle("Starts a game", isOn: $partnerGameStarted).font(.subheadline)
                }

                SectionCard {
                    Toggle("Results are ready", isOn: $partnerGameResultsReady).font(.subheadline)
                    Text("Sent once you've both finished a game and can see how you matched.")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }

                SectionCard {
                    Toggle("Finishes their answers first", isOn: $partnerGamePartnerFinished).font(.subheadline)
                    Text("Sent when \(appModel.partner.name) finishes a game before you do, so you know it's your turn.")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
                }

                SectionCard {
                    Toggle("Daily streak reminder", isOn: $dailyStreakReminder).font(.subheadline)
                    Text("A nudge if today's Daily Activity question hasn't been answered yet.")
                        .font(.caption2)
                        .foregroundStyle(Theme.subtleInk)
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
        .onChange(of: partnerGameResultsReady) { _, _ in saveIfLoaded() }
        .onChange(of: partnerGamePartnerFinished) { _, _ in saveIfLoaded() }
        .onChange(of: dailyStreakReminder) { _, _ in saveIfLoaded() }
        .onChange(of: partnerInviteReminder) { _, _ in saveIfLoaded() }
        .postHogScreenView("Settings: Notification Preferences")
    }

    private func load() async {
        loadFailed = false
        if let prefs = try? await BackendService.fetchCoupleNotificationPreferences() {
            partnerDrawingSaved = prefs.partnerDrawingSaved
            partnerTripAdded = prefs.partnerTripAdded
            partnerMemoryAdded = prefs.partnerMemoryAdded
            partnerGameStarted = prefs.partnerGameStarted
            partnerGameResultsReady = prefs.partnerGameResultsReady
            partnerGamePartnerFinished = prefs.partnerGamePartnerFinished
            dailyStreakReminder = prefs.dailyStreakReminder
            partnerInviteReminder = prefs.partnerInviteReminder
            // Only set once real preferences are actually in hand — otherwise the next single
            // toggle flip's `saveIfLoaded()` would upsert all 8 fields at their hardcoded `true`
            // defaults, silently reverting any previously-saved `false` preference on the
            // backend.
            isLoaded = true
        } else {
            loadFailed = true
        }
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
            partnerGameStarted: partnerGameStarted,
            partnerGameResultsReady: partnerGameResultsReady,
            partnerGamePartnerFinished: partnerGamePartnerFinished,
            dailyStreakReminder: dailyStreakReminder,
            partnerInviteReminder: partnerInviteReminder
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
