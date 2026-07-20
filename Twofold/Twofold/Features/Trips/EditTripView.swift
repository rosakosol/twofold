//
//  EditTripView.swift
//  Twofold
//
//  Full edit of a trip's own fields — origin/destination/dates/category/notes/traveler.
//  AddTripDetailsView is creation-only (bundled with its own add-a-flight sub-flow), so this is
//  a focused sibling for editing an already-existing trip rather than reworking that flow to
//  serve two purposes.
//

import PostHog
import SwiftUI

struct EditTripView: View {
    let trip: Trip

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var origin: Place?
    @State private var destination: Place?
    @State private var departureDate: Date
    @State private var arrivalDate: Date
    @State private var isReunionTrip: Bool
    @State private var traveler: TripTraveler
    @State private var notes: String
    @State private var isSaving = false

    init(trip: Trip) {
        self.trip = trip
        _origin = State(initialValue: trip.origin)
        _destination = State(initialValue: trip.destination)
        _departureDate = State(initialValue: trip.departureDate)
        _arrivalDate = State(initialValue: trip.arrivalDate)
        _isReunionTrip = State(initialValue: trip.isReunionTrip)
        _notes = State(initialValue: trip.notes ?? "")
        _traveler = State(initialValue: .you)
    }

    private var canSave: Bool {
        origin != nil && destination != nil && !isSaving
    }

    var body: some View {
        Form {
            Section {
                CityMenuPicker(label: "From", selection: $origin)
                CityMenuPicker(label: "To", selection: $destination)
            }

            Section {
                DatePicker("Departing", selection: $departureDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("Returning", selection: $arrivalDate, in: departureDate..., displayedComponents: [.date, .hourAndMinute])
                    // See AddTripDetailsView's identical `.onChange` — the `in:` bound alone
                    // doesn't retroactively re-clamp `arrivalDate` when `departureDate` moves
                    // past it.
                    .onChange(of: departureDate) { _, newValue in
                        if arrivalDate < newValue { arrivalDate = newValue }
                    }
            }

            Section {
                Picker("Who's travelling?", selection: $traveler) {
                    Text(appModel.currentUser.name).tag(TripTraveler.you)
                    Text(appModel.partner.name).tag(TripTraveler.partner)
                    Text("Both").tag(TripTraveler.both)
                }
                .pickerStyle(.segmented)
                Toggle("Is this a reunion trip?", isOn: $isReunionTrip)
            }

            Section("Notes") {
                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
        .navigationTitle("Edit Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save").fontWeight(.semibold)
                    }
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            let ids = Set(trip.travelerIDs)
            if ids == Set([appModel.currentUser.id, appModel.partner.id]) {
                traveler = .both
            } else if ids.contains(appModel.partner.id) {
                traveler = .partner
            } else {
                traveler = .you
            }
        }
        .postHogScreenView("Travel: Edit Trip")
    }

    private func save() {
        guard let origin, let destination else { return }
        isSaving = true
        var updated = trip
        updated.origin = origin
        updated.destination = destination
        updated.departureDate = departureDate
        updated.arrivalDate = arrivalDate
        updated.isReunionTrip = isReunionTrip
        updated.travelerIDs = {
            switch traveler {
            case .you: return [appModel.currentUser.id]
            case .partner: return [appModel.partner.id]
            case .both: return [appModel.currentUser.id, appModel.partner.id]
            }
        }()
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        Task {
            await appModel.updateTrip(updated)
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        EditTripView(trip: MockData.reunionTrip)
    }
    .environment(AppModel())
}
