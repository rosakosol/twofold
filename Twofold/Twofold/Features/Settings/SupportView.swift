//
//  SupportView.swift
//  Twofold
//
//  FAQ (fetched from faq_entries — see HelpService.fetchFAQ, editable server-side without an
//  app release) plus a "Still need help?" entry into SendSupportRequestView for anything the
//  FAQ doesn't answer.
//

import PostHog
import SwiftUI

struct SupportView: View {
    @State private var faqEntries: [FAQEntry] = []
    @State private var isLoadingFAQ = true
    @State private var loadError: String?
    @State private var showingSupportForm = false

    /// Groups preserve each row's own fetch-order (`.order("sort_order")`) within a group; groups
    /// themselves are ordered by their first (lowest-sortOrder) entry, so category order is
    /// controlled entirely by each row's `sort_order` — no separate category-ordering column.
    private var groupedFAQ: [(category: String, entries: [FAQEntry])] {
        let grouped = Dictionary(grouping: faqEntries) { $0.category ?? "General" }
        return grouped
            .map { (category: $0.key, entries: $0.value) }
            .sorted { ($0.entries.first?.sortOrder ?? .max) < ($1.entries.first?.sortOrder ?? .max) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if isLoadingFAQ {
                    ProgressView().frame(maxWidth: .infinity).padding(Theme.Spacing.xl)
                } else if let loadError {
                    Text(loadError).font(.caption).foregroundStyle(Theme.subtleInk)
                } else {
                    ForEach(groupedFAQ, id: \.category) { group in
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text(group.category).font(.subheadline.weight(.bold)).foregroundStyle(Theme.subtleInk)
                            SectionCard {
                                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider() }
                                    FAQRow(entry: entry)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Still need help?").font(.subheadline.weight(.bold)).foregroundStyle(Theme.subtleInk)
                    SectionCard {
                        Button {
                            showingSupportForm = true
                        } label: {
                            SettingsRow(title: "Contact Support", systemImage: "envelope.fill", showsChevron: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFAQ() }
        .sheet(isPresented: $showingSupportForm) {
            SendSupportRequestView()
        }
        .postHogScreenView("Settings: Support")
    }

    private func loadFAQ() async {
        do {
            faqEntries = try await HelpService.fetchFAQ()
        } catch {
            loadError = "Couldn't load FAQs right now."
        }
        isLoadingFAQ = false
    }
}

private struct FAQRow: View {
    let entry: FAQEntry
    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(alignment: .top) {
                    Text(entry.question).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer(minLength: Theme.Spacing.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                if isExpanded {
                    Text(entry.answer).font(.caption).foregroundStyle(Theme.subtleInk)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SupportView()
    }
}
