//
//  AddTripDetailsView.swift
//  Twofold
//
//  Shared by the onboarding "add our next trip" step and the home screen's
//  progressive "Add your next trip" checklist card — the caller decides what
//  happens after saving via `onSave`.
//

import SwiftUI

struct AddTripDetailsView: View {
    enum Mode {
        case onboarding
        case standalone
    }

    /// Seeds initial field values — used by the flight-email review flow to prefill
    /// whatever the parser confidently extracted, leaving the rest for manual entry.
    struct Prefill {
        var origin: Place?
        var destination: Place?
        var departureDate: Date?
        var returnDate: Date?
        var flightNumber: String?
    }

    var mode: Mode
    var partnerName: String = "Partner"
    var onSave: (Trip) -> Void = { _ in }
    /// Onboarding-only "skip for now" affordance — `nil` (the default) renders no secondary
    /// button, so the two non-onboarding call sites (home screen checklist, flight-email review
    /// flow) are unaffected.
    var onSkip: (() -> Void)?

    @Environment(AppModel.self) private var appModel
    @State private var origin: Place?
    @State private var destination: Place?
    @State private var departureDate: Date
    @State private var returnDate: Date
    @State private var traveler: TripTraveler = .you
    @State private var isReunionTrip: Bool = true
    @State private var flightNumberHint: String
    @State private var selectedFlightCandidate: AeroFlightCandidate?
    @State private var showingAddFlightFlow = false
    @State private var isSaving = false

    /// Manual-entry fallback dates only (30/44 days out) get their time-of-day pinned to 9am —
    /// a deliberate, predictable default rather than whatever moment this screen happened to be
    /// opened at. Prefilled dates (from the flight-email review flow) keep their real parsed
    /// time untouched, since those already reflect an actual flight's actual schedule.
    private static func nineAM(on date: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    init(mode: Mode, partnerName: String = "Partner", prefill: Prefill? = nil, onSave: @escaping (Trip) -> Void = { _ in }, onSkip: (() -> Void)? = nil) {
        self.mode = mode
        self.partnerName = partnerName
        self.onSave = onSave
        self.onSkip = onSkip
        _origin = State(initialValue: prefill?.origin)
        _destination = State(initialValue: prefill?.destination)
        _departureDate = State(initialValue: prefill?.departureDate ?? Self.nineAM(on: Date().addingTimeInterval(86_400 * 30)))
        _returnDate = State(initialValue: prefill?.returnDate ?? prefill?.departureDate?.addingTimeInterval(86_400 * 14) ?? Self.nineAM(on: Date().addingTimeInterval(86_400 * 44)))
        _flightNumberHint = State(initialValue: prefill?.flightNumber ?? "")
    }

    var body: some View {
        OnboardingScaffold(
            title: "Add a trip",
            subtitle: mode == .onboarding ? "This is a natural first step — you can always add more trips later." : nil,
            content: {
                VStack(spacing: Theme.Spacing.md) {
                    addFlightRow

                    CityMenuPicker(label: "From", selection: $origin)
                    CityMenuPicker(label: "To", selection: $destination)

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("When?").font(.caption).foregroundStyle(Theme.subtleInk)
                        DatePicker("Departing", selection: $departureDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Returning", selection: $returnDate, in: departureDate..., displayedComponents: [.date, .hourAndMinute])
                            // The `in: departureDate...` bound above only constrains what this
                            // picker itself can scroll to — SwiftUI doesn't retroactively
                            // re-clamp `returnDate` when `departureDate` changes later, so a
                            // Departing pushed past an already-chosen Returning would otherwise
                            // save with the return date before the departure date.
                            .onChange(of: departureDate) { _, newValue in
                                if returnDate < newValue { returnDate = newValue }
                            }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Who's travelling?").font(.caption).foregroundStyle(Theme.subtleInk)
                        Picker("Who's travelling?", selection: $traveler) {
                            Text("You").tag(TripTraveler.you)
                            // Disabled (not just warned-about) outside onboarding — same
                            // reasoning as `FlightConfirmationView`'s picker: post-onboarding,
                            // `appModel.partner` being a placeholder with no real profile behind
                            // it means selecting it shouldn't even be possible. Still fully
                            // enabled during onboarding itself, where not having a partner
                            // connected yet is the expected, normal state, not a problem to flag.
                            Text(partnerName).tag(TripTraveler.partner)
                                .disabled(mode == .standalone && !appModel.partnerConnected)
                            Text("Both").tag(TripTraveler.both)
                                .disabled(mode == .standalone && !appModel.partnerConnected)
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Is this a reunion trip?", isOn: $isReunionTrip)
                        .padding(Theme.Spacing.md)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                }
            },
            primaryTitle: "Save trip",
            primaryAction: save,
            primaryDisabled: origin == nil || destination == nil || isSaving,
            secondaryTitle: onSkip != nil ? "Skip for now" : nil,
            secondaryAction: onSkip
        )
        .sheet(isPresented: $showingAddFlightFlow) {
            AddFlightFlowView(
                nearCoordinate: origin?.coordinate,
                initialFlightNumberDigits: flightNumberHint.isEmpty ? nil : flightNumberHint,
                topBarTitle: "Cancel",
                onTopBarAction: { showingAddFlightFlow = false },
                completion: .handOff { candidate in
                    selectedFlightCandidate = candidate
                    showingAddFlightFlow = false
                }
            )
        }
    }

    /// Tapping through opens the real AeroAPI-backed AddFlightFlowView search (the same wizard
    /// used elsewhere in the app) — flights are never self-reported, so a flight only ever
    /// attaches to this trip once a real candidate comes back from that search. When this view
    /// was opened from the forwarded-flight-email review flow, whatever number the parser
    /// picked out of the email is shown as a hint and pre-fills the search rather than being
    /// saved as-is.
    private var addFlightRow: some View {
        Button {
            showingAddFlightFlow = true
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                if let candidate = selectedFlightCandidate {
                    AirlineLogoView(url: candidate.logoURL, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayFlightNumber)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        if let originCity = candidate.origin?.city, let destinationCity = candidate.destination?.city {
                            Text("\(originCity) to \(destinationCity)")
                                .font(.caption)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Button {
                        selectedFlightCandidate = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.subtleInk)
                    }
                } else {
                    Image(systemName: "airplane")
                        .foregroundStyle(Theme.skyBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flightNumberHint.isEmpty ? "Add a flight" : flightNumberHint)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        if !flightNumberHint.isEmpty {
                            Text("From your forwarded email — tap to find and confirm")
                                .font(.caption2)
                                .foregroundStyle(Theme.subtleInk)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
            }
            .padding()
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        guard let origin, let destination else { return }
        isSaving = true
        Task {
            // Real AeroAPI-tracked flight only — no self-reported fallback. `addTrip` handles
            // attaching it, including the case where there's no couple yet (e.g. onboarding,
            // before pairing) — it queues the candidate and attaches it once the trip is
            // actually inserted server-side, rather than silently dropping it.
            let trip = await appModel.addTrip(
                origin: origin,
                destination: destination,
                departureDate: departureDate,
                arrivalDate: returnDate,
                traveler: traveler,
                isReunionTrip: isReunionTrip,
                flightCandidate: selectedFlightCandidate
            )
            isSaving = false
            onSave(trip)
        }
    }
}

#Preview {
    NavigationStack {
        AddTripDetailsView(mode: .onboarding)
    }
    .environment(AppModel())
}
