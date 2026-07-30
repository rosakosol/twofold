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
    @State private var streakEndingReminder = true
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
                    groupHeader("Travel")
                    toggleRow(
                        "My partner adds a trip",
                        isOn: $partnerTripAdded,
                        caption: "Flight updates have their own notification settings on each tracked flight."
                    )
                }

                SectionCard {
                    groupHeader("Memories")
                    toggleRow("My partner adds a memory", isOn: $partnerMemoryAdded)
                    toggleRow("My partner saves a drawing", isOn: $partnerDrawingSaved)
                }

                SectionCard {
                    groupHeader("Games")
                    toggleRow("My partner starts a game", isOn: $partnerGameStarted)
                    toggleRow(
                        "Your results are ready",
                        isOn: $partnerGameResultsReady,
                        caption: "Sent once you've both finished a game and can see how you matched."
                    )
                    toggleRow(
                        "My partner finishes first",
                        isOn: $partnerGamePartnerFinished,
                        caption: "Sent when your partner finishes before you, so you know it's your turn."
                    )
                    toggleRow(
                        "Daily deep question reminder",
                        isOn: $dailyStreakReminder,
                        caption: "A nudge if today's question hasn't been answered yet."
                    )
                    toggleRow(
                        "Streak ending soon",
                        isOn: $streakEndingReminder,
                        caption: "A last-chance nudge about 1 hour before today's streak runs out."
                    )
                }
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
        .onChange(of: streakEndingReminder) { _, _ in saveIfLoaded() }
        .onChange(of: partnerInviteReminder) { _, _ in saveIfLoaded() }
        .postHogScreenView("Settings: Notification Preferences")
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.subtleInk)
    }

    /// Wraps a toggle and its optional caption in their own tight-spaced VStack, so
    /// grouping several rows inside one SectionCard doesn't space a row's own caption
    /// the same as the gap to the *next* row (SectionCard applies one uniform spacing
    /// between all of its direct children).
    private func toggleRow(_ label: String, isOn: Binding<Bool>, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(label, isOn: isOn).font(.subheadline)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(Theme.subtleInk)
            }
        }
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
            streakEndingReminder = prefs.streakEndingReminder
            partnerInviteReminder = prefs.partnerInviteReminder
            // Only set once real preferences are actually in hand — otherwise the next single
            // toggle flip's `saveIfLoaded()` would upsert every field at its hardcoded `true`
            // default, silently reverting any previously-saved `false` preference on the
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
            streakEndingReminder: streakEndingReminder,
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
