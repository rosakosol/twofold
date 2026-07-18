//
//  AboutUsView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct AboutUsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                TwofoldBrandMark(size: 56, textStyle: .title)
                    .padding(.top, Theme.Spacing.xl)

                SectionCard {
                    Image("rosa")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .frame(maxWidth: .infinity)

                    Text(
                        """
                        Hi! I'm Rosa, the founder of Twofold.

                        I'm a 25-year-old developer based in Melbourne, Australia, with a passion for building apps that make a genuine difference. 

                        Having experienced the highs and lows of a long-distance relationship myself, I often wished there was an easier way to keep track of my partner's flights and celebrate the journey we were sharing. 
                        
                        That's what inspired Twofold - a place to map, remember, and visualise the story of our relationship, and hopefully yours too.
                        
                        Thank you so much for being part of the journey. If you're enjoying Twofold, I'd really appreciate it if you could leave a rating or review on the App Store. Your feedback helps shape the future of the app and means a lot as an independent developer.
                        
                        Thanks for being here, and happy travels ❤️
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("About Us")
        .navigationBarTitleDisplayMode(.inline)
        .postHogScreenView("Settings: About Us")
    }
}

#Preview {
    NavigationStack {
        AboutUsView()
    }
}
