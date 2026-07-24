//
//  LinkMemoryPickerView.swift
//  Twofold
//
//  Memories have no automatic association with a trip (no place/date matching) — this is the
//  only way a memory ever gets linked to one, offering memories not already linked elsewhere —
//  or, via "Create a new memory", starting a brand new one that's linked to this trip the moment
//  it's saved.
//

import PostHog
import SwiftUI

struct LinkMemoryPickerView: View {
    let trip: Trip

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateMemory = false

    private var unlinkedMemories: [Memory] {
        appModel.memories.filter { $0.tripID == nil }.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingCreateMemory = true
                    } label: {
                        Label("Create a new memory", systemImage: "plus.circle.fill")
                    }
                }
                Section("Unlinked memories") {
                    if unlinkedMemories.isEmpty {
                        Text("Every memory is already linked to a trip.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    } else {
                        ForEach(unlinkedMemories) { memory in
                            Button {
                                Task {
                                    await appModel.linkMemory(memory, to: trip)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    MemoryPhotoView(memory: memory, cornerRadius: 10)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(memory.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(1)
                                        Text(memory.date, format: .dateTime.day().month(.abbreviated).year())
                                            .font(.caption)
                                            .foregroundStyle(Theme.subtleInk)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Link a Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showingCreateMemory) {
            AddMemoryView(linkToTrip: trip, onSaved: { dismiss() })
        }
        .postHogScreenView("Travel: Link Memory")
    }
}

#Preview {
    LinkMemoryPickerView(trip: MockData.reunionTrip)
        .environment(AppModel())
}
