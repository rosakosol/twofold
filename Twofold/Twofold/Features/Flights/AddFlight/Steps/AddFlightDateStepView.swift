//
//  AddFlightDateStepView.swift
//  Twofold
//
//  Today/Tomorrow/Calendar quick-picks are always the real selection mechanism; the free-text
//  field is a convenience layer on top via NSDataDetector (Foundation, no new dependency) —
//  it degrades safely to the quick-picks if the typed text doesn't parse as a date.
//
//  What the typed date needed and did not have was a way out of this screen. It wrote straight into
//  `model.date` on every keystroke and stopped there: nothing advanced, nothing confirmed, and
//  nothing on screen even acknowledged that "30/9" had been understood. Every other route off this
//  step — Today, Tomorrow, the calendar's Done — pushes `.results`, so typing looked like the one
//  input that did nothing. It now shows what it read back as a row you can tap, and Return does the
//  same thing.
//

import SwiftUI
import PostHog

struct AddFlightDateStepView: View {
    @Environment(AddFlightFlowModel.self) private var model
    @State private var query = ""
    @State private var showingCalendar = false
    /// Held rather than written straight through to `model.date`. Typing is transient — "3" on the
    /// way to "30/9" parses as nothing, and a half-finished date should not quietly become the
    /// selection. It is committed when it is chosen.
    @State private var parsedDate: Date?

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today }

    var body: some View {
        AddFlightStepScaffold(subtitle: "Enter departure date") {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if model.mode == .route {
                    HStack(spacing: Theme.Spacing.xs) {
                        if let departure = model.departureAirport {
                            PillBadge(text: departure.preferredCode ?? departure.cityOrName, tint: Theme.skyBlue)
                        }
                        if let destination = model.destinationAirport {
                            PillBadge(text: destination.preferredCode ?? destination.cityOrName, tint: Theme.skyBlue)
                        }
                    }
                }

                TextField("30/9 or Friday", text: $query)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .padding()
                    .themedCardBackground(cornerRadius: Theme.Radius.card)
                    .onChange(of: query) { _, newValue in parsedDate = Self.date(from: newValue) }
                    .onSubmit { if let parsedDate { commit(parsedDate) } }

                if let parsedDate {
                    parsedDateRow(parsedDate)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    dateRow(title: "Today", date: today)
                    dateRow(title: "Tomorrow", date: tomorrow)

                    Button {
                        showingCalendar = true
                    } label: {
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(Theme.skyBlue)
                            Text("Pick from Calendar").foregroundStyle(Theme.ink)
                            Spacer()
                        }
                        .padding()
                        .themedCardBackground(cornerRadius: Theme.Radius.card)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingCalendar) {
            NavigationStack {
                DatePicker(
                    "Departure date",
                    selection: Binding(get: { model.date }, set: { model.date = $0 }),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Departure date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showingCalendar = false
                            model.path.append(.results)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .postHogScreenView("Flights: Add Flight — Date")
    }

    /// The same shape as the entry step's "Detected flight number" row: it repeats what was
    /// understood, in full, so a misread is obvious before it is acted on — "10/5" is May the 10th
    /// to this app and October the 5th to half the world.
    private func parsedDateRow(_ date: Date) -> some View {
        Button {
            commit(date)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.title3)
                    .foregroundStyle(Theme.leafGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Tap to search this date")
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.subtleInk)
            }
            .padding()
            .themedCardBackground(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    private func commit(_ date: Date) {
        model.date = date
        model.path.append(.results)
    }

    private func dateRow(title: String, date: Date) -> some View {
        let isSelected = Calendar.current.isDate(model.date, inSameDayAs: date)
        return Button {
            model.date = date
            model.path.append(.results)
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Theme.leafGreen : Theme.subtleInk)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Text(date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.caption)
                        .foregroundStyle(Theme.subtleInk)
                }
                Spacer()
            }
            .padding()
            .themedCardBackground(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }

    /// NSDataDetector reads these in the device's own locale and resolves a bare day/month to the
    /// next time it comes around, which is what someone typing a departure date means: on 6
    /// September, "30/9" is this month's 30th and "10/5" is next May.
    static func date(from text: String) -> Date? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, range: range)?.date
    }
}
