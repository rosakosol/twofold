//
//  BirthdayView.swift
//  Twofold
//
//  When your birthday is, so your partner can be reminded of it and the app can mark the day.
//
//  Optional, and visibly so. Every other question in this stretch of onboarding has one obvious
//  answer the person already knows; this one is the first that somebody might simply not want to
//  give, and a date of birth typed into an app because there was no way past the screen is worse
//  than no date at all. So Skip sits under the button rather than behind a back swipe.
//
//  Only the day and month are kept — see migration 20261110001300. Worth saying on the screen
//  rather than only in the schema, because "birthday" and "date of birth" mean different things to
//  people and only one of them is being asked for here.
//

import SwiftUI

struct BirthdayView: View {
    @Environment(OnboardingModel.self) private var onboarding

    /// The wheels always show something, so a separate flag carries "they have actually chosen".
    /// Without it Continue would accept 1 January from somebody who never touched the screen —
    /// which is what `pickedDate: Date?` was doing for the `DatePicker` this replaced.
    @State private var hasChosen = false
    @State private var month = 1
    @State private var day = 1

    /// A leap year, so 29 February is offered. Only used to count days in a month; no year is ever
    /// read out of this screen.
    private static let leapYear = 2024

    var body: some View {
        OnboardingScaffold(
            title: "When's your birthday?",
            subtitle: "We'll remind \(partnerLabel) so it doesn't slip past. Just the day and month — we never ask for the year.",
            centered: true,
            content: {
                // Two wheels rather than a `DatePicker`. SwiftUI has no month-and-day date picker —
                // `.date` always shows a year — so the screen asked for a year directly underneath a
                // sentence promising it never would, and `Birthday(date:)` then threw it away. The
                // schema has no column for it either (20261110001300 is month and day, no year).
                HStack(spacing: 0) {
                    Picker("Month", selection: Binding(get: { month }, set: { newValue in
                        month = newValue
                        // February after picking the 30th has no 30th. Clamping rather than
                        // refusing, because the wheel cannot show an invalid row to correct.
                        day = min(day, Self.dayCount(in: newValue))
                        hasChosen = true
                    })) {
                        ForEach(1...12, id: \.self) { number in
                            Text(Self.monthName(number)).tag(number)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)

                    Picker("Day", selection: Binding(get: { day }, set: { day = $0; hasChosen = true })) {
                        ForEach(1...Self.dayCount(in: month), id: \.self) { number in
                            Text("\(number)").tag(number)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxWidth: .infinity)
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            },
            primaryTitle: "Continue",
            primaryAction: {
                onboarding.birthday = Birthday(month: month, day: day)
                onboarding.path.append(.coupleLocations)
            },
            primaryDisabled: !hasChosen,
            // Leaves `onboarding.birthday` nil rather than writing anything. Skipping is a real
            // answer here, not a deferral, and nothing later treats the absence as unfinished.
            secondaryTitle: "Skip for now",
            secondaryAction: {
                onboarding.birthday = nil
                onboarding.path.append(.coupleLocations)
            }
        )
    }

    /// Days in a month, counted in a leap year so 29 February is reachable for anyone born on it.
    private static func dayCount(in month: Int) -> Int {
        var components = DateComponents()
        components.year = leapYear
        components.month = month
        guard let date = Calendar.current.date(from: components),
              let range = Calendar.current.range(of: .day, in: .month, for: date) else { return 31 }
        return range.count
    }

    /// The locale's own month names, so this reads as a date to whoever is looking at it.
    private static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.monthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
    }

    /// Their name once it has been given — this screen sits after `PartnerNameView` — and a
    /// neutral word before it, rather than a sentence with a hole in it.
    private var partnerLabel: String {
        onboarding.partnerName.isEmpty ? "your partner" : onboarding.partnerName
    }
}

#Preview {
    NavigationStack {
        BirthdayView()
    }
    .environment(OnboardingModel())
}
