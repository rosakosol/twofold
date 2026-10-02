//
//  StatTile.swift
//  Twofold
//

import SwiftUI

struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle().fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)

            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    HStack {
        StatTile(icon: "airplane", value: "9", label: "Trips")
        StatTile(icon: "globe", value: "4", label: "Countries", tint: Theme.success)
        StatTile(icon: "heart.fill", value: "127", label: "Days together", tint: Theme.coral)
    }
    .padding()
}
