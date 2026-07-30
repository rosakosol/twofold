//
//  ShareCardAppearancePicker.swift
//  Twofold
//
//  Lets the user force a stats share card (Relationship/Trip/Flight/per-stat) to light or dark
//  regardless of the device's own system appearance — same sun/moon segmented-button styling as
//  `DistanceShareView.themePicker`, just two options instead of three since these cards only ever
//  need light/dark, not a separate accent theme.
//

import SwiftUI

struct ShareCardAppearancePicker: View {
    @Binding var selection: ColorScheme

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            option(.light, icon: "sun.max.fill", label: "Light")
            option(.dark, icon: "moon.stars.fill", label: "Dark")
        }
    }

    private func option(_ scheme: ColorScheme, icon: String, label: String) -> some View {
        Button {
            selection = scheme
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(selection == scheme ? Theme.skyBlue : Theme.cardBackground, in: Circle())
                    .foregroundStyle(selection == scheme ? .white : Theme.ink)
                Text(label).font(.caption2)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ShareCardAppearancePicker(selection: .constant(.light))
        .padding()
        .background(Theme.backgroundGradient)
}
