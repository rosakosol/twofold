//
//  SettingsFooterView.swift
//  Twofold
//
//  Static content at the bottom of the Settings scroll — not a row, no navigation. Legal links
//  point at draft placeholder pages on the marketing site (clearly labeled there as pending
//  legal review) so the navigation is real end-to-end rather than a dead link.
//

import SwiftUI

struct SettingsFooterView: View {
    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Link("Privacy Policy", destination: URL(string: "https://www.twofoldapp.com.au/privacy.html")!)
                Text("·").foregroundStyle(Theme.subtleInk)
                Link("Terms of Use", destination: URL(string: "https://www.twofoldapp.com.au/terms.html")!)
            }
            .font(.caption)

            Text(versionLabel)
                .font(.caption2)
                .foregroundStyle(Theme.subtleInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
    }
}

#Preview {
    SettingsFooterView()
}
