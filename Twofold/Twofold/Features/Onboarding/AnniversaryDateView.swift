//
//  AnniversaryDateView.swift
//  Twofold
//
//  Collected as personalization (like home city) before a real couple exists — persisted to
//  `profiles.anniversary_date` in `AppModel.applyOnboardingAccount`, and reflected into
//  `Couple.startedDatingOn` locally so `AppModel.stats.daysTogether` has something real to
//  compute from immediately. Reconciling this with `couples.started_dating_on` once a real
//  pairing happens is follow-up work. Also the intended source for a future anniversary/days-
//  together widget.
//

import SwiftUI

struct AnniversaryDateView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var date: Date = Calendar.current.date(byAdding: .year, value: -1, to: .now) ?? .now

    /// Couples in the same city skip the (now-removed) "Home is {city}" reward screen and go
    /// straight to the notifications sell screen — that screen only has something meaningful
    /// to show (real km/time-difference) when the two cities actually differ.
    private var sameCity: Bool {
        guard let mine = onboarding.homeCity, let theirs = onboarding.partnerCity else { return false }
        return mine.city == theirs.city && mine.country == theirs.country
    }

    var body: some View {
        OnboardingScaffold(
            title: "When did your story begin? 💕",
            subtitle: "We'll use this for your anniversary countdown and widgets.",
            centered: true,
            content: {
                DatePicker("Together since", selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.anniversaryDate = date
                onboarding.path.append(sameCity ? .notificationsSell : .personalizedInsight)
            }
        )
        .onAppear {
            if let existing = onboarding.anniversaryDate {
                date = existing
            }
        }
    }
}

#Preview {
    NavigationStack {
        AnniversaryDateView()
    }
    .environment(OnboardingModel())
}
