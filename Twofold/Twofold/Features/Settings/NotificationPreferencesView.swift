//
//  NotificationPreferencesView.swift
//  Twofold
//
//  Global "notify me when my partner..." toggles — separate from FlightTrackingView's own
//  per-flight notification toggles, which stay scoped to each individual tracked flight.
//

import PostHog
import SwiftUI
import UIKit
import UserNotifications

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
    /// The one-time onboarding "Keep me updated" screen is the *only* other place in the app
    /// that ever calls `requestAuthorization` — anyone who didn't pass through it (an account
    /// that predates that screen, or just denied it once) has no way back to system permission
    /// without this. iOS also only lists the app under Settings → Notifications at all once
    /// `requestAuthorization` has been called at least once, so `.notDetermined` here explains a
    /// real "there's no notifications entry for Twofold in Settings" report — not a delivery bug,
    /// a permission-was-never-requested bug. All the toggles below are silently meaningless while
    /// this is anything other than `.authorized`/`.provisional`/`.ephemeral`.
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingPermission = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                if loadFailed {
                    SectionCard {
                        Text("Couldn't load your notification settings.").font(.subheadline)
                        Button("Retry") { Task { await load() } }
                    }
                }

                permissionBanner

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
        .task { await refreshAuthStatus() }
        // Returning from Settings.app (after using the "Open Settings" banner button below, or
        // just switching apps and back) is the one moment a changed system permission wouldn't
        // otherwise be noticed until this view happened to reload.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshAuthStatus() }
        }
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

    /// `.notDetermined` (never asked — either this account predates the onboarding permission
    /// screen, or it just hasn't come up yet) gets a direct in-app request, since iOS still
    /// allows that. `.denied` (asked before and said no, or silently never-showed for some other
    /// reason) can only be fixed in Settings.app — iOS won't let an app re-prompt once denied.
    @ViewBuilder
    private var permissionBanner: some View {
        switch authStatus {
        case .notDetermined:
            SectionCard {
                Text("Notifications aren't turned on yet").font(.subheadline.weight(.semibold))
                Text("None of the toggles below can do anything until you allow notifications for Twofold.")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                Button {
                    Task { await requestPermission() }
                } label: {
                    if isRequestingPermission {
                        ProgressView()
                    } else {
                        Text("Turn on notifications")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.skyBlue)
                .disabled(isRequestingPermission)
            }
        case .denied:
            SectionCard {
                Text("Notifications are off for Twofold").font(.subheadline.weight(.semibold))
                Text("Enable them in iOS Settings to hear from \(appModel.partner.name).")
                    .font(.caption2)
                    .foregroundStyle(Theme.subtleInk)
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.skyBlue)
            }
        case .authorized, .provisional, .ephemeral:
            EmptyView()
        @unknown default:
            EmptyView()
        }
    }

    private func refreshAuthStatus() async {
        authStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Same call as `NotificationsSellView.requestPermission()` — this is that same one-time
    /// system prompt, just reachable from Settings too for anyone who missed it during
    /// onboarding. Registers the device for remote notifications regardless of the user's
    /// choice, matching `PushNotificationDelegate`'s existing unconditional launch-time call.
    private func requestPermission() async {
        isRequestingPermission = true
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthStatus()
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        isRequestingPermission = false
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
