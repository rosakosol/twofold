//
//  OfflineNoticeView.swift
//  Twofold
//
//  Shown once when the app opens with no connection.
//
//  Offline the app is genuinely usable — games, memories, trips and drawings all work, and
//  everything queues to sync — but nothing said so, and a screen full of last-known data with no
//  explanation reads as an app that has half-loaded and stalled. This says which half is missing
//  and that the rest will catch up on its own, so the answer to "is it broken?" is on screen
//  rather than inferred.
//

import SwiftUI

struct OfflineNoticeView: View {
    @Environment(\.dismiss) private var dismiss

    /// What still works, in the order someone is most likely to reach for it.
    private let available: [(icon: String, text: String)] = [
        ("gamecontroller.fill", "Play games — answers send when you're back"),
        ("photo.on.rectangle.angled", "Add memories, with photos"),
        ("airplane", "Add trips"),
        ("scribble.variable", "Draw on your pad"),
    ]

    private let unavailable: [(icon: String, text: String)] = [
        ("magnifyingglass", "Searching for flights or places"),
        ("arrow.triangle.2.circlepath", "Live flight tracking and your partner's updates"),
    ]

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(Theme.skyBlue.opacity(0.18))
                                .frame(width: 116, height: 116)
                                .blur(radius: 16)
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundStyle(Theme.skyBlue)
                        }

                        Text("You're offline")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Twofold still works. Anything you add is saved on this device and sent as soon as you're back online.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, Theme.Spacing.lg)
                    }

                    section(title: "You can still", rows: available, tint: Theme.leafGreen, symbol: "checkmark")
                    section(title: "Not until you're back", rows: unavailable, tint: Theme.subtleInk, symbol: nil)
                }
                .padding(.top, Theme.Spacing.xl)
            }

            Button {
                dismiss()
            } label: {
                Text("Got it")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.skyBlue, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func section(title: String, rows: [(icon: String, text: String)], tint: Color, symbol: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(Theme.subtleInk)

            ForEach(rows, id: \.text) { row in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: symbol ?? row.icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                        .frame(width: 22)
                    Text(row.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCardBackground(cornerRadius: Theme.Radius.card)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        OfflineNoticeView()
    }
}
