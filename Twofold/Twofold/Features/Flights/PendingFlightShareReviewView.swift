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
            Text("Something went wrong reading this email")
                .font(.headline)
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
            extracted = try await FlightEmailParsingService.parse(text: share.rawText)
        } catch {
            extracted = nil
        }
        isLoading = false
    }

    private func prefill(from extracted: ExtractedFlightDetails) -> AddTripDetailsView.Prefill {
        AddTripDetailsView.Prefill(
            origin: extracted.matchedOrigin,
            destination: extracted.matchedDestination,
            departureDate: extracted.departureDate,
            returnDate: extracted.arrivalDate,
            flightNumber: extracted.flightNumber
        )
    }

    private func finish() {
        PendingShareStore.remove(id: share.id)
        dismiss()
    }
}

#Preview {
    PendingFlightShareReviewView(share: PendingFlightShare(rawText: "QF35 SIN to MEL, 14 Sep 2026, 10:20am"))
        .environment(AppModel())
}
