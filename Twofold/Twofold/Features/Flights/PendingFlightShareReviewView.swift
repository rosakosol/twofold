//
//  PendingFlightShareReviewView.swift
//  Twofold
//
//  Parses a queued share and hands the result to AddTripDetailsView as a prefill —
//  the user always reviews/edits before anything is saved, since parsed data can be
//  wrong and this writes into a shared couple space.
//

import SwiftUI
import PostHog

struct PendingFlightShareReviewView: View {
    let share: PendingFlightShare

    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var extracted: ExtractedFlightDetails?
    /// What the server said, when it said something worth repeating — the parse limit and an
    /// over-long email both explain themselves, and `failureView`'s generic headline does not.
    @State private var failureMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Reading flight details…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let extracted {
                    AddTripDetailsView(
                        mode: .standalone,
                        partnerName: appModel.partner.name,
                        prefill: prefill(from: extracted),
                        onSave: { _ in finish() }
                    )
                } else {
                    failureView
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Review flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { finish() }
                }
            }
        }
        .task { await load() }
        .postHogScreenView("Flights: Shared Flight Review")
    }

    private var failureView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "envelope.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(Theme.subtleInk)
            Text(failureMessage ?? "Something went wrong reading this email")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Add manually instead") {
                extracted = ExtractedFlightDetails()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        do {
            extracted = try await FlightEmailParsingService.parse(
                subject: share.subject,
                body: share.bodyText,
                pdfText: share.pdfText
            )
        } catch {
            extracted = nil
            // Only a message the server actually chose to send. Anything else keeps the generic
            // headline rather than surfacing a URLError or a decoding failure at the person.
            if case let FlightEmailParsingError.rejected(message) = error {
                failureMessage = message
            }
        }
        isLoading = false
    }

    private func prefill(from extracted: ExtractedFlightDetails) -> AddTripDetailsView.Prefill {
        // `extracted.arrivalDate` is this same flight's own landing time (a few hours after
        // departure), not a real return-trip date — passing it as `returnDate` would prefill
        // "Returning" to the same day as "Departing". Leaving it nil instead lets
        // `AddTripDetailsView`'s own init fall back to departure + 14 days, same as manual entry.
        AddTripDetailsView.Prefill(
            origin: extracted.matchedOrigin,
            destination: extracted.matchedDestination,
            departureDate: extracted.departureDate,
            flightNumber: extracted.flightNumber
        )
    }

    private func finish() {
        PendingShareStore.remove(id: share.id)
        dismiss()
    }
}

#Preview {
    PendingFlightShareReviewView(share: PendingFlightShare(bodyText: "QF35 SIN to MEL, 14 Sep 2026, 10:20am"))
        .environment(AppModel())
}
