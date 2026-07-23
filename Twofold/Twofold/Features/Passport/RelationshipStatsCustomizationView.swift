//
//  RelationshipStatsCustomizationView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct RelationshipStatsCustomizationView: View {
    @Binding var backgroundTheme: RelationshipStatsCardBackground
    @Binding var showTripsChip: Bool
    @Binding var showReunionsChip: Bool
    @Binding var showMemoriesChip: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    SectionCard {
                        Text("Background").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        backgroundSwatches
                    }

                    SectionCard {
                        Text("Stats to include").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.subtleInk)
                        Toggle("Trips", isOn: $showTripsChip)
                        Divider()
                        Toggle("Reunions", isOn: $showReunionsChip)
                        Divider()
                        Toggle("Memories", isOn: $showMemoriesChip)
                    }
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

    private var backgroundSwatches: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(RelationshipStatsCardBackground.allCases) { theme in
                Button {
                    backgroundTheme = theme
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        Circle()
                            .fill(LinearGradient(colors: theme.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .overlay {
                                // A faint outline even when unselected — `.classic`'s swatch is
                                // white, which would otherwise be invisible against this card's
                                // own light background.
                                Circle().strokeBorder(Theme.ink.opacity(backgroundTheme == theme ? 0.8 : 0.15), lineWidth: 2.5)
                            }
                            .overlay {
                                if backgroundTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(theme == .classic ? Theme.ink : .white)
                                }
                            }
                        Text(theme.rawValue)
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    RelationshipStatsCustomizationView(
        backgroundTheme: .constant(.auto),
        showTripsChip: .constant(true),
        showReunionsChip: .constant(true),
        showMemoriesChip: .constant(true)
    )
}
