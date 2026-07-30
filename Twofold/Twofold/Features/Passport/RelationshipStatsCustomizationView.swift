//
//  RelationshipStatsCustomizationView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct RelationshipStatsCustomizationView: View {
    @Binding var showTripsChip: Bool
    @Binding var showReunionsChip: Bool
    @Binding var showMemoriesChip: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                SectionCard {
                    Text("Stats to include").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                    Toggle("Trips", isOn: $showTripsChip)
                    Divider()
                    Toggle("Reunions", isOn: $showReunionsChip)
                    Divider()
                    Toggle("Memories", isOn: $showMemoriesChip)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .postHogScreenView("Passport: Customize Share Card")
    }
}

#Preview {
    RelationshipStatsCustomizationView(
        showTripsChip: .constant(true),
        showReunionsChip: .constant(true),
        showMemoriesChip: .constant(true)
    )
}
