//
//  AddFlightDateStepView.swift
//  Twofold
//
//  Today/Tomorrow/Calendar quick-picks are always the real selection mechanism; the free-text
//  field is a convenience layer on top via NSDataDetector (Foundation, no new dependency) —
//  it degrades safely to the quick-picks if the typed text doesn't parse as a date.
//

import SwiftUI
import PostHog

struct AddFlightDateStepView: View {
    @Environment(AddFlightFlowModel.self) private var model
    @State private var query = ""
    @State private var showingCalendar = false

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

                TextField("10/5 or Friday", text: $query)
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .onChange(of: query) { _, newValue in applyNaturalLanguageDate(newValue) }

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
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func applyNaturalLanguageDate(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), let date = match.date else { return }
        model.date = date
    }
}
