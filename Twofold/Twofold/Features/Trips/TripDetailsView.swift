//
//  TripDetailsView.swift
//  Twofold
//
//  Pushed from TripsListView when any trip row is tapped — previously an "active" trip (one
//  with a linked flight currently being tracked) skipped straight to FlightTrackingView with no
//  trip-level screen at all; this is now the consistent first stop for every trip, with the
//  linked flight (if any) one tap deeper from here.
//
//  Derives its displayed trip live from `appModel.trips` (keyed by id) rather than holding its
//  own copy, so edits/links/deletes made from this screen — or anywhere else — are reflected
//  immediately without needing manual refresh plumbing.
//

import PostHog
import SwiftUI

struct TripDetailsView: View {
    let tripID: UUID

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirm = false
    @State private var showingLinkFlightPicker = false
    @State private var showingLinkMemoryPicker = false
    @State private var isDeleting = false

    init(trip: Trip) {
        self.tripID = trip.id
    }

    private var trip: Trip? {
        appModel.trips.first { $0.id == tripID }
    }

    private var travelers: [Person] {
        guard let trip else { return [appModel.currentUser] }
        let people = trip.travelerIDs.compactMap { appModel.couple.partner($0) }
        return people.isEmpty ? [appModel.currentUser] : people
    }

    private var linkedMemories: [Memory] {
        appModel.memories.filter { $0.tripID == tripID }.sorted { $0.date < $1.date }
    }

    var body: some View {
        Group {
            if let trip {
                content(trip)
            } else {
                ContentUnavailableView("Trip no longer available", systemImage: "airplane.departure")
            }
        }
        .navigationTitle("Trip Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if trip != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit Trip", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Trip", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let trip {
                NavigationStack { EditTripView(trip: trip) }
            }
        }
        .sheet(isPresented: $showingLinkFlightPicker) {
            if let trip {
                LinkFlightPickerView(trip: trip)
            }
        }
        .sheet(isPresented: $showingLinkMemoryPicker) {
            if let trip {
                LinkMemoryPickerView(trip: trip)
            }
        }
        .alert("Delete this trip?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                guard let trip else { return }
                isDeleting = true
                Task {
                    await appModel.deleteTrip(trip)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Any linked flight or memories stay saved - they'll just no longer be linked to this trip.")
        }
        .postHogScreenView("Travel: Trip Details")
    }

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                header(trip)
                notesSection(trip)
                flightSection(trip)
                memoriesSection(trip)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
    }

    private func header(_ trip: Trip) -> some View {
        SectionCard {
            HStack(spacing: Theme.Spacing.md) {
                if travelers.count > 1 {
                    HStack(spacing: -14) {
                        ForEach(travelers) { person in
                            AvatarView(person: person, size: 44)
                                .overlay(Circle().stroke(Theme.cardBackground, lineWidth: 2))
                        }
                    }
                } else {
                    AvatarView(person: travelers[0], size: 52)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(travelers.map(\.name).joined(separator: " & "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.subtleInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(trip.origin.city)
                        Image(systemName: "arrow.right")
                        Text(trip.destination.city)
                    }
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                PillBadge(text: trip.isReunionTrip ? "Reunion" : "Trip", tint: Theme.skyBlue)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Departs").font(.caption).foregroundStyle(Theme.subtleInk)
                    Text(trip.departureDate, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline.weight(.medium))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Returns").font(.caption).foregroundStyle(Theme.subtleInk)
                    Text(trip.arrivalDate, format: .dateTime.day().month(.abbreviated).year())
                        .font(.subheadline.weight(.medium))
                }
            }

            HStack {
                Text("Distance").font(.caption).foregroundStyle(Theme.subtleInk)
                Spacer()
                Text(MeasurementPreference.distanceLabel(km: trip.distanceKm)).font(.subheadline.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ trip: Trip) -> some View {
        if let notes = trip.notes, !notes.isEmpty {
            SectionCard {
                Text("Notes").font(.subheadline.weight(.semibold))
                Text(notes).font(.subheadline).foregroundStyle(Theme.ink)
            }
        }
    }

    private func flightSection(_ trip: Trip) -> some View {
        SectionCard {
            HStack {
                Text("Flight").font(.subheadline.weight(.semibold))
                Spacer()
                if trip.flight == nil {
                    Button("Link a flight") { showingLinkFlightPicker = true }
                        .font(.caption.weight(.semibold))
                }
            }

            if let flight = trip.flight {
                NavigationLink {
                    FlightTrackingView(flight: flight)
                } label: {
                    FlightRowView(flight: flight)
                }
                .buttonStyle(.plain)

                Button(role: .destructive) {
                    Task { await appModel.unlinkFlight(flight) }
                } label: {
                    Text("Unlink flight").font(.caption)
                }
            } else {
                Text("No flight linked yet.").font(.caption).foregroundStyle(Theme.subtleInk)
            }
        }
    }

    private func memoriesSection(_ trip: Trip) -> some View {
        SectionCard {
            HStack {
                Text("Memories").font(.subheadline.weight(.semibold))
                Spacer()
                Button("Link a memory") { showingLinkMemoryPicker = true }
                    .font(.caption.weight(.semibold))
            }

            if linkedMemories.isEmpty {
                Text("No memories linked yet.").font(.caption).foregroundStyle(Theme.subtleInk)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(linkedMemories) { memory in
                            NavigationLink {
                                MemoryDetailView(memory: memory)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    MemoryPhotoView(memory: memory, cornerRadius: 12)
                                        .frame(width: 88, height: 88)
                                    Text(memory.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .foregroundStyle(Theme.ink)
                                        .frame(width: 88, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await appModel.unlinkMemory(memory) }
                                } label: {
                                    Label("Unlink from trip", systemImage: "link.badge.minus")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailsView(trip: MockData.reunionTrip)
    }
    .environment(AppModel())
}
