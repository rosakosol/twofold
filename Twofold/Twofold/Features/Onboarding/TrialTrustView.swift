//
//  TrialTrustView.swift
//  Twofold
//

import SwiftUI

struct TrialTrustView: View {
    @Environment(OnboardingModel.self) private var onboarding
    @State private var shownRows: Set<Int> = []
    @State private var iconPulsing = false

    private let timeline: [(label: String, title: String, subtitle: String, icon: String)] = [
        ("TODAY", "Unlock all Twofold features", "Track flights, follow journeys and stay connected.", "lock.open.fill"),
        ("DAY 10", "We'll send you a reminder", "No surprises.", "bell.fill"),
        ("DAY 14", "Your membership begins", "Cancel anytime before.", "checkmark.seal.fill"),
    ]

    var body: some View {
        OnboardingScaffold(
            title: "We want you to try Twofold for free",
            centered: true,
            content: {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    // Same pulsing GlobeHeart mark as the welcome screen, bookending onboarding.
                    Image("GlobeHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .scaleEffect(iconPulsing ? 1.08 : 1.0)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                                iconPulsing = true
                            }
                        }

                    VStack(spacing: Theme.Spacing.lg) {
                        ForEach(Array(timeline.enumerated()), id: \.offset) { index, row in
                            timelineRow(label: row.label, title: row.title, subtitle: row.subtitle, icon: row.icon)
                                .opacity(shownRows.contains(index) ? 1 : 0)
                                .offset(x: shownRows.contains(index) ? 0 : -16)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear {
                        for index in timeline.indices {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.15 + Double(index) * 0.15)) {
                                _ = shownRows.insert(index)
                            }
                        }
                    }

                    Text("We'll remind you before your free trial ends.")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            },
            primaryTitle: "Continue for free",
            // `.paywall`, not `.saveAccount` — the account screen already happened earlier in
            // the flow (after the widget sell), so going there again looped users back to sign-in.
            primaryAction: { onboarding.path.append(.paywall) }
        )
    }

    private func timelineRow(label: String, title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.skyBlue.opacity(0.15))
                Image(systemName: icon).foregroundStyle(Theme.skyBlue)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(Theme.subtleInk)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(Theme.subtleInk)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack {
        TrialTrustView()
    }
    .environment({
        let model = OnboardingModel()
        model.firstName = "You"
        model.partnerName = "Erin"
        model.homeCity = Place.commonCities.first { $0.city == "Melbourne" }
        model.partnerCity = Place.commonCities.first { $0.city == "London" }
        return model
    }())
}
