//
//  AboutUsView.swift
//  Twofold
//

import SwiftUI

struct AboutUsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                TwofoldBrandMark(size: 56, textStyle: .title)
                    .padding(.top, Theme.Spacing.xl)

                SectionCard {
                    Text(
                        "Twofold turns a long-distance relationship into a living map. Track flights, watch the distance between you close, and relive every trip you've taken to see each other."
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                }

                SectionCard {
                    Text("Made with love, for couples navigating distance.")
                        .font(.footnote)
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("About Us")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AboutUsView()
    }
}
