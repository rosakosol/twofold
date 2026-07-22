//
//  MemoriesListView.swift
//  Twofold
//
//  Shared list used both as the Memories tab's List mode and as the destination when a map
//  marker is tapped (pre-filtered to that location). Groups memories by month, newest first,
//  with a right-edge year index that scrolls on tap and highlights as you scroll.
//
//  A real `List` (not a plain ScrollView), specifically so single-item swipe-to-delete
//  (`.swipeActions`, UIKit-backed) disambiguates correctly against the list's own vertical
//  scroll — a hand-rolled horizontal DragGesture here would fight the ScrollView's pan
//  recognizer the same way SwipeChoiceCard's did before that got an axis-aware fix. Styled to
//  look identical to the old ScrollView+LazyVStack version via listRowInsets/listRowBackground/
//  listRowSeparator rather than the system List chrome.
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

    /// Long-press any row to enter this — every row grows a selection circle, tapping toggles
    /// membership instead of navigating, and a toolbar offers bulk delete. Swipe-to-delete
    /// (single memory, no mode change) only applies while this is false.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Memory.ID> = []
    @State private var showingBulkDeleteConfirm = false
    @State private var hapticTrigger = false

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

    /// Extra trailing inset reserved so row content (and the swipe-action reveal) never sits
    /// under the year scrubber overlay.
    private var trailingRowInset: CGFloat {
        availableYears.count > 1 ? 32 : Theme.Spacing.md
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
                        List {
                            if monthGroups.isEmpty {
                                noMatchState
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            } else {
                                ForEach(monthGroups) { group in
                                    Section {
                                        ForEach(group.memories) { memory in
                                            row(memory)
                                        }
                                    } header: {
                                        Text(group.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.subtleInk)
                                            .textCase(nil)
                                            .listRowInsets(EdgeInsets(top: Theme.Spacing.sm, leading: Theme.Spacing.md, bottom: Theme.Spacing.xs, trailing: 0))
                                            .onAppear { currentVisibleYear = group.year }
                                    }
                                    .id(group.id)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .environment(\.defaultMinListRowHeight, 0)
                        .safeAreaPadding(.bottom, 64)
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
        .sensoryFeedback(.selection, trigger: hapticTrigger)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        withAnimation(.snappy) {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingBulkDeleteConfirm = true
                    } label: {
                        Text("Delete (\(selectedIDs.count))")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .alert(
            selectedIDs.count == 1 ? "Delete this memory?" : "Delete \(selectedIDs.count) memories?",
            isPresented: $showingBulkDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { deleteSelection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
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

    // MARK: - Rows

    /// Swaps between a plain toggle-selection `Button` (selecting mode) and the regular
    /// `NavigationLink` + swipe-to-delete (normal mode) — same `memoryRow` content either way.
    /// Long-pressing while *not* selecting enters selection mode with that row pre-selected,
    /// the same "long-press to start a multi-select" convention Photos/Files use.
    @ViewBuilder
    private func row(_ memory: Memory) -> some View {
        Group {
            if isSelecting {
                Button {
                    toggleSelection(memory)
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        selectionIndicator(isSelected: selectedIDs.contains(memory.id))
                        memoryRow(memory)
                    }
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    MemoryDetailView(memory: memory)
                } label: {
                    memoryRow(memory)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await appModel.deleteMemory(memory) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .onLongPressGesture {
                    hapticTrigger.toggle()
                    withAnimation(.snappy) {
                        isSelecting = true
                        selectedIDs = [memory.id]
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.md, bottom: Theme.Spacing.sm, trailing: trailingRowInset))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func selectionIndicator(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? Theme.skyBlue : Theme.subtleInk.opacity(0.35))
    }

    private func toggleSelection(_ memory: Memory) {
        hapticTrigger.toggle()
        if selectedIDs.contains(memory.id) {
            selectedIDs.remove(memory.id)
        } else {
            selectedIDs.insert(memory.id)
        }
    }

    private func deleteSelection() {
        let toDelete = appModel.memories.filter { selectedIDs.contains($0.id) }
        Task {
            await appModel.deleteMemories(toDelete)
            isSelecting = false
            selectedIDs.removeAll()
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
