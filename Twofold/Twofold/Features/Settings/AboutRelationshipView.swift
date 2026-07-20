//
//  AboutRelationshipView.swift
//  Twofold
//
//  Couple-level settings — currently just the anniversary date. Split out of SettingsView as
//  part of the Settings/Profile IA restructure. This is the sole place anniversary editing
//  lives once a couple is connected — PartnerSetupView keeps its own copy only for the
//  pre-connection first-time-setup flow, so getting a partner set up doesn't require bouncing
//  between two screens.
//

import PostHog
import SwiftUI

struct AboutRelationshipView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var anniversaryDate: Date = .now
    @State private var isSaving = false
    @State private var showingHappyAnniversary = false

    /// End of today, not the live `Date.now` instant — see `AnniversaryDateView.latestSelectableDate`
    /// for why bounding at the exact live instant silently makes "today" unreachable once the
    /// picker's held time-of-day (here, whatever `couple.startedDatingOn`'s time component is)
    /// sits later in the day than the current clock time.
    private var latestSelectableDate: Date {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfToday) ?? .now
    }

    /// See `AnniversaryDateView.isAnniversaryToday` — month+day match against today, not
    /// `Calendar.isDateInToday` (which also requires the year to match, essentially never true
    /// for a real multi-year anniversary).
    private var isAnniversaryToday: Bool {
        let calendar = Calendar.current
        let picked = calendar.dateComponents([.month, .day], from: anniversaryDate)
        let today = calendar.dateComponents([.month, .day], from: .now)
        return picked.month == today.month && picked.day == today.day
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.md) {
                SectionCard {
                    Text("Anniversary").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                    DatePicker("Together since", selection: $anniversaryDate, in: ...latestSelectableDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("About Your Relationship")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }
        }
        .onAppear {
            anniversaryDate = appModel.couple.startedDatingOn
        }
        .postHogScreenView("Settings: About Relationship")
        .fullScreenCover(isPresented: $showingHappyAnniversary, onDismiss: dismiss.callAsFunction) {
            HappyAnniversaryView(
                years: max(0, Calendar.current.dateComponents([.year], from: anniversaryDate, to: .now).year ?? 0),
                onContinue: { showingHappyAnniversary = false }
            )
        }
    }

    private func save() {
        isSaving = true
        Task {
            await appModel.updateAnniversaryDate(anniversaryDate)
            isSaving = false
            if isAnniversaryToday {
                showingHappyAnniversary = true
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AboutRelationshipView()
    }
    .environment(AppModel())
}
