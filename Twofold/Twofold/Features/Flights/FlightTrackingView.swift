//
//  FlightTrackingView.swift
//  Twofold
//

import SwiftUI
import Supabase

struct FlightTrackingView: View {
    let trip: Trip
    @Environment(AppModel.self) private var appModel
    @State private var notifyOnLanding = true
    @State private var updates: [FlightUpdate] = []
    @State private var noteDraft = ""
    @State private var isSendingUpdate = false
    @State private var channel: RealtimeChannelV2?

    private var flight: Flight? { trip.flight }

    private var traveler: Person? {
        appModel.couple.partner(trip.travelerID)
    }

    /// Only the traveler on this trip can log updates about their own journey — their
    /// partner watches, but doesn't report on someone else's flight.
    private var isTraveler: Bool {
        appModel.currentUser.id == trip.travelerID
    }

    private var timeRemainingLabel: String {
        guard let flight else { return "" }
        let totalSeconds = Int(flight.timeRemaining)
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text(flight?.status.emotionalHeadline ?? "On the way")
                        .font(.title2.weight(.bold))
                    if let flight {
                        Text("\(flight.flightNumber) · \(flight.origin.city) to \(flight.destination.city)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                    }
                }
                .frame(maxWidth: .infinity)

                SectionCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Text("Landing in")
                            .font(.subheadline)
                            .foregroundStyle(Theme.subtleInk)
                        Text(timeRemainingLabel)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        if let flight {
                            Text(flight.scheduledArrival, format: .dateTime.hour().minute())
                                .font(.subheadline)
                                .foregroundStyle(Theme.subtleInk)
                        }

                        HStack {
                            Image(systemName: "airplane")
                                .font(.title2)
                                .foregroundStyle(Theme.skyBlue)
                            Spacer()
                        }
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Theme.skyBlue.opacity(0.2))
                                    .frame(height: 4)
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(Theme.skyBlue)
                                            .frame(width: proxy.size.width * (flight?.progress ?? 0), height: 4)
                                    }
                            }
                            .frame(height: 4)
                            .padding(.top, 18)
                        }

                        HStack {
                            Text(trip.origin.iataCode ?? trip.origin.city)
                            Spacer()
                            Text(trip.destination.iataCode ?? trip.destination.city)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let flight {
                    SectionCard {
                        ForEach(Array(flight.timeline.enumerated()), id: \.element.id) { index, event in
                            TimelineRow(event: event, isLast: index == flight.timeline.count - 1)
                        }
                    }

                    if isTraveler {
                        logUpdateCard
                    }

                    if !updates.isEmpty {
                        updatesCard
                    }
                }

                SectionCard {
                    Toggle("Get notified when they land", isOn: $notifyOnLanding)
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(traveler.map { "\($0.name)'s journey" } ?? "Their journey")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAndSubscribe() }
        .onDisappear {
            if let channel {
                Task { await BackendService.unsubscribe(channel) }
            }
        }
    }

    private var logUpdateCard: some View {
        SectionCard {
            Text("Log an update")
                .font(.subheadline.weight(.semibold))

            TextField("Add a note (optional)", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

            HStack(spacing: Theme.Spacing.sm) {
                ForEach([FlightUpdateKind.mealService, .disruption, .goingToSleep], id: \.self) { kind in
                    Button {
                        logUpdate(kind: kind)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.icon)
                                .font(.subheadline.weight(.semibold))
                            Text(kind.label)
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(colors: kind.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .disabled(isSendingUpdate)
                }
            }
        }
    }

    private var updatesCard: some View {
        SectionCard {
            Text("Updates")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(updates) { update in
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(LinearGradient(colors: update.kind.iconGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                            Image(systemName: update.kind.icon)
                                .foregroundStyle(.white)
                                .font(.caption)
                        }
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(update.kind.label).font(.subheadline.weight(.semibold))
                            if let note = update.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(Theme.subtleInk)
                            }
                        }

                        Spacer(minLength: 0)

                        Text(update.createdAt, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(Theme.subtleInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func logUpdate(kind: FlightUpdateKind) {
        guard let flight else { return }
        let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = FlightUpdate(kind: kind, note: note.isEmpty ? kind.defaultNote : note)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            updates.insert(update, at: 0)
        }
        noteDraft = ""
        isSendingUpdate = true
        Task {
            try? await BackendService.insertFlightUpdate(flightID: flight.id, kind: update.kind, note: update.note)
            isSendingUpdate = false
        }
    }

    private func loadAndSubscribe() async {
        guard let flight else { return }
        if let fetched = try? await BackendService.fetchFlightUpdates(flightID: flight.id) {
            updates = fetched
        }
        let (channel, stream) = BackendService.subscribeToFlightUpdates(flightID: flight.id)
        self.channel = channel
        for await update in stream where !updates.contains(where: { $0.id == update.id }) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                updates.insert(update, at: 0)
            }
        }
    }
}

#Preview {
    NavigationStack {
        FlightTrackingView(trip: MockData.reunionTrip)
    }
    .environment(AppModel())
}
