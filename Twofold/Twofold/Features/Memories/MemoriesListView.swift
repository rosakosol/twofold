//
//  MemoriesListView.swift
//  Twofold
//
//  Shared list used both as the Memories tab's List mode and as the destination when a map
//  marker is tapped (pre-filtered to that location). Groups memories by month, newest first,
//  with a right-edge year index that scrolls on tap and highlights as you scroll.
//

import PostHog
import SwiftUI

struct MemoriesListView: View {
    /// Set only when pushed from a map marker tap — drives this screen's own nav title (the
    /// tab-mode case leaves the outer "Memories" title from `MemoriesView` untouched).
    private let initialLocationFilter: Place?
    var onTapAddMemory: () -> Void = {}

    @Environment(AppModel.self) private var appModel
    @State private var locationFilter: Place?
    @State private var yearFilter: Int?
    @State private var currentVisibleYear: Int?

    init(initialLocationFilter: Place? = nil, onTapAddMemory: @escaping () -> Void = {}) {
        self.initialLocationFilter = initialLocationFilter
        self.onTapAddMemory = onTapAddMemory
        _locationFilter = State(initialValue: initialLocationFilter)
    }

    private struct MonthGroup: Identifiable {
        let year: Int
        let month: Int
        var memories: [Memory]
        var id: String { "\(year)-\(month)" }
        var title: String {
            let date = Calendar.current.date(from: DateComponents(year: year, month: month)) ?? .now
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private var filteredMemories: [Memory] {
        appModel.memories.filter { memory in
            if let locationFilter, memory.place?.id != locationFilter.id { return false }
            if let yearFilter, Calendar.current.component(.year, from: memory.date) != yearFilter { return false }
            return true
        }
    }

    private var monthGroups: [MonthGroup] {
        let grouped = Dictionary(grouping: filteredMemories) { memory in
            Calendar.current.dateComponents([.year, .month], from: memory.date)
        }
        return grouped
            .map { key, memories in MonthGroup(year: key.year ?? 0, month: key.month ?? 0, memories: memories.sorted { $0.date > $1.date }) }
            .sorted { ($0.year, $0.month) > ($1.year, $1.month) }
    }

    private var availableYears: [Int] {
        Array(Set(appModel.memories.map { Calendar.current.component(.year, from: $0.date) })).sorted(by: >)
    }

    @ViewBuilder
    var body: some View {
        if let initialLocationFilter {
            content
                .navigationTitle(initialLocationFilter.city)
                .navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if appModel.memories.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                                if monthGroups.isEmpty {
                                    noMatchState
                                } else {
                                    ForEach(monthGroups) { group in
                                        monthSection(group).id(group.id)
                                    }
                                }
                            }
                            .padding(.leading, Theme.Spacing.md)
                            .padding(.trailing, availableYears.count > 1 ? 32 : Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.sm)
                            .padding(.bottom, 64)
                        }
                        .overlay(alignment: .trailing) {
                            if availableYears.count > 1 {
                                yearScrubber { year in
                                    guard let target = monthGroups.first(where: { $0.year == year }) else { return }
                                    withAnimation(.snappy) { proxy.scrollTo(target.id, anchor: .top) }
                                }
                                .padding(.trailing, 6)
                            }
                        }
                    }
                }
            }
        }
        .postHogScreenView("Memories: List")
    }

    // MARK: - Filters

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Menu {
                Button("All locations") { locationFilter = nil }
                ForEach(appModel.citiesWithMemories) { city in
                    Button(city.city) { locationFilter = city }
                }
            } label: {
                filterChip(text: locationFilter?.city ?? "All locations", icon: "mappin")
            }

            Menu {
                Button("All time") { yearFilter = nil }
                ForEach(availableYears, id: \.self) { year in
                    Button(String(year)) { yearFilter = year }
                }
            } label: {
                filterChip(text: yearFilter.map(String.init) ?? "All time", icon: "calendar")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func filterChip(text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption.weight(.medium))
            Image(systemName: "chevron.down").font(.caption2)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.ink)
        .background(Theme.cardBackground, in: Capsule())
    }

    // MARK: - Year scrubber

    private func yearScrubber(onSelect: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 8) {
            ForEach(availableYears, id: \.self) { year in
                Button {
                    onSelect(year)
                } label: {
                    Text(String(year).suffix(2))
                        .font(.caption2.weight(currentVisibleYear == year ? .bold : .regular))
                        .foregroundStyle(currentVisibleYear == year ? Theme.skyBlue : Theme.subtleInk)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, 4)
    }

    // MARK: - Sections / rows

    private func monthSection(_ group: MonthGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(group.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.subtleInk)
                .onAppear { currentVisibleYear = group.year }

            ForEach(group.memories) { memory in
                NavigationLink {
                    MemoryDetailView(memory: memory)
                } label: {
                    memoryRow(memory)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await appModel.deleteMemory(memory) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func memoryRow(_ memory: Memory) -> some View {
        SectionCard {
            // `.center`, not `.top` — a memory with no `place` shows two lines of text instead of
            // three, and centering keeps the photo aligned with that shorter text column instead
            // of pinned to the row's top edge with visible empty space below it. Deliberately
            // excludes the note/description (title, location, date only) so every row's height
            // stays consistent regardless of how long a memory's note is.
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                MemoryPhotoView(memory: memory, cornerRadius: 14)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let place = memory.place {
                        Text(place.city)
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                            .lineLimit(1)
                    }
                    Text(memory.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.trailing, Theme.Spacing.md)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTapAddMemory) {
                SectionCard {
                    HStack(spacing: Theme.Spacing.md) {
                        ZStack {
                            Circle().fill(Theme.skyBlue.opacity(0.15))
                            Image(systemName: "photo.badge.plus").foregroundStyle(Theme.skyBlue)
                        }
                        .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your first memory").font(.headline).foregroundStyle(Theme.ink)
                            Text("Tap to save a photo from a moment together.")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.sm)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private var noMatchState: some View {
        Text("No memories match these filters.")
            .font(.subheadline)
            .foregroundStyle(Theme.subtleInk)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Spacing.xl)
    }
}

#Preview {
    NavigationStack {
        MemoriesListView()
            .environment(AppModel())
            .background(Theme.backgroundGradient.ignoresSafeArea())
    }
}
