//
//  SetupChecklistCard.swift
//  Twofold
//
//  Home's "Finish setting up Twofold" list.
//

import SwiftUI

struct SetupChecklistCard: View {
    @Environment(AppModel.self) private var appModel

    let onAddTrip: () -> Void
    let onAddFlight: () -> Void
    let onTurnOnLocation: () -> Void

    @ViewBuilder
    var body: some View {
        // Trip/flight rows need a connected partner to make sense — the dedicated
        // `PartnerStatusSection`'s invite card already owns that prompt, so this checklist only ever shows
        // those two rows once a partner exists. "Turn on location access" is independent of
        // partner status and still shows regardless.
        // `hasLoadedCoupleState` first: `needsFirstTrip` is `trips.isEmpty` and `needsFirstFlight`
        // reads the same empty array, so before the fetch this card confidently told everyone to add
        // their first trip and flight — including couples with fifty of each.
        if appModel.session.hasLoadedCoupleState, !appModel.prompts.setupChecklistDismissed, !checklistItems.isEmpty {
            SectionCard {
                // One child, not two. `SectionCard` spaces its children by `md` (16), which is
                // right between a card's distinct parts — but the header here is not a distinct
                // part, it is the list's own title, and the 44pt dismiss button already inflates
                // that row well past the text it contains. The two together left this card with a
                // gap no other card has, wide enough to read as a missing row.
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Finish setting up Twofold")
                            .font(.headline)
                        Spacer()
                        Button {
                            appModel.prompts.dismissSetupChecklist()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.controlLine)
                                // The glyph alone is ~22pt, half Apple's 44pt minimum — a miss on this
                                // one dismisses nothing and taps the card behind it instead. The frame
                                // only grows the tap target; `contentShape` makes the whole of it
                                // hittable rather than just the glyph's own pixels, and the icon keeps
                                // its original size.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Cancels the padding the 44pt box adds on the trailing side, so the icon still
                        // sits where it did against the card's edge.
                        .padding(.trailing, -Theme.Spacing.xs)
                        .accessibilityLabel("Dismiss")
                    }

                    // Rows flush against each other, separated by a rule rather than by space —
                    // each already carries a 44pt tap target, so a gap on top of that put three
                    // items in a card tall enough to look padded by mistake, with spaces wide
                    // enough to read as tappable while hitting nothing. The rule does the
                    // separating that the space was failing to do, the same way `nextReunionCard`
                    // divides its two halves.
                    VStack(spacing: 0) {
                        ForEach(Array(checklistItems.enumerated()), id: \.element.id) { index, item in
                            // Between rows only. A divider written next to each row would leave a
                            // stray rule above the first or below the last, and which row is first
                            // changes as they get completed.
                            if index > 0 {
                                Divider()
                            }
                            checklistRow(task: item.task, action: item.action)
                        }
                    }
                }
            }
        }
    }

    /// One row of the setup checklist.
    ///
    /// The rows are gathered into a list rather than written as three `if`s inside the stack, so
    /// that the dividers can sit *between* them. Inline conditionals give no way to ask whether a
    /// given row is the first one still showing — and that changes as rows get completed, so it
    /// cannot be hard-coded either.
    private struct ChecklistItem: Identifiable {
        let task: ChecklistTask
        let action: () -> Void
        var id: String { task.rawValue }
    }

    /// The three rows, as cases rather than as strings.
    ///
    /// The titles used to be `String`s on `ChecklistItem`, handed to `Text(title)`. That renders
    /// perfectly and never reaches `Localizable.xcstrings`: Xcode extracts a literal written inside
    /// `Text`, not a `String` variable that arrives there, so these three shipped permanently
    /// untranslated with nothing to indicate it. Same shape as `GatedFeature` in
    /// `SubscriptionRequiredView`, for the same reason.
    private enum ChecklistTask: String {
        case trip
        case flight
        case location

        var title: Text {
            switch self {
            case .trip: Text("Add your next trip")
            case .flight: Text("Add your first flight")
            case .location: Text("Turn on location access")
            }
        }

        /// The icon travels with the case too, so adding a row is one place rather than two.
        var icon: ChecklistIcon {
            switch self {
            case .trip: .system("airplane.departure")
            case .flight: .asset("boarding-pass")
            case .location: .system("location")
            }
        }
    }

    /// Trip and flight rows need a connected partner to make sense — see `setupChecklistCard`,
    /// which uses the same conditions to decide whether the card appears at all.
    private var checklistItems: [ChecklistItem] {
        var items: [ChecklistItem] = []
        if appModel.session.partnerConnected, appModel.needsFirstTrip {
            items.append(ChecklistItem(task: .trip, action: onAddTrip))
        }
        if appModel.session.partnerConnected, appModel.needsFirstFlight {
            items.append(ChecklistItem(task: .flight, action: onAddFlight))
        }
        // Own city only. This row is an instruction to use this device's location permission, so
        // it has no business appearing when the city that is missing is the partner's — see
        // `AppModel.needsOwnHomeCity`.
        if appModel.needsOwnHomeCity {
            items.append(ChecklistItem(task: .location, action: onTurnOnLocation))
        }
        return items
    }

    enum ChecklistIcon {
        case system(String)
        case asset(String)
    }

    private func checklistRow(task: ChecklistTask, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Group {
                    switch task.icon {
                    case .asset(let name):
                        Image(name)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    case .system(let name):
                        Image(systemName: name)
                    }
                }
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

                task.title
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            // A single line of `.subheadline` is around 20pt tall, so these rows were roughly half
            // the 44pt minimum — and the gap between two of them was dead space that looked
            // tappable. `contentShape` also makes the empty stretch between the title and the
            // chevron hit the button, rather than only the text and glyphs themselves.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
