//
//  SettingsRow.swift
//  Twofold
//
//  Single-row pattern reused across the Settings/Profile IA — replaces the hand-rolled
//  `HStack { Label(...); Spacer(); Image(systemName: "chevron.right") }` that used to be
//  copy-pasted in SettingsView/PartnerSetupView. Wrap in a NavigationLink for a pushed
//  screen, or a plain Button for an action row (Rate us, Share the app, Help) — this view
//  is just the label content, not the tap target itself.
//

import SwiftUI

struct SettingsRow: View {
    var title: String
    var systemImage: String
    var value: String?
    var isDestructive: Bool = false
    var showsChevron: Bool = true
    var isLoading: Bool = false

    var body: some View {
        HStack {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(isDestructive ? Theme.heartRed : Theme.ink)
                Spacer()
                if let value {
                    Text(value).foregroundStyle(Theme.subtleInk)
                }
                if showsChevron {
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.subtleInk)
                }
            }
        }
    }
}
