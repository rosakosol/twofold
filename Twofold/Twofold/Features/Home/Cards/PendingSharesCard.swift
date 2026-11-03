//
//  PendingSharesCard.swift
//  Twofold
//
//  Home's prompt to review flight emails shared in from Mail.
//

import SwiftUI

struct PendingSharesCard: View {
    let shares: [PendingFlightShare]
    let onReview: (PendingFlightShare) -> Void

    @ViewBuilder
    var body: some View {
        if let first = shares.first {
            SectionCard {
                Button {
                    onReview(first)
                } label: {
                    HStack {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.15))
                            Image(systemName: "envelope.badge").foregroundStyle(Theme.accent)
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(shares.count == 1 ? "1 flight email to review" : "\(shares.count) flight emails to review")
                                .font(.headline)
                            Text("Shared from Mail — tap to add the flight")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
