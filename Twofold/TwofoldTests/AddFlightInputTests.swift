//
//  AddFlightInputTests.swift
//  TwofoldTests
//
//  What the Add Flight flow sends to a billed endpoint.
//
//  Every search is one or more AeroAPI requests, charged whether or not the input made sense. So
//  the thing worth pinning is not that a well-formed search works — it is that a malformed one
//  never leaves the device.
//

import Testing
import Foundation
@testable import Twofold

@MainActor
struct AddFlightInputTests {

    private func model(_ initial: String? = nil) -> AddFlightFlowModel {
        AddFlightFlowModel(
            nearCoordinate: nil,
            topBarTitle: "Cancel",
            onTopBarAction: {},
            initialFlightNumberDigits: initial
        )
    }

    /// The search sends `airline.iata + flightNumberDigits`. Letters in the digits half produce a
    /// designator like "QFQF123" — malformed, billed, and answered with "no flights found" for a
    /// flight that exists.
    ///
    /// `FlightNumberStepView`'s field is `.numberPad`, which shapes the on-screen keyboard and
    /// stops nothing else: paste, a hardware keyboard and dictation all put letters in. Every other
    /// writer already filtered; the one a person types into did not.
    @Test("letters cannot reach the flight number")
    func lettersAreRejected() {
        let m = model()
        m.flightNumberDigits = "QF123"
        #expect(m.flightNumberDigits == "123", "a pasted airline code must not survive into the search")
    }

    @Test("nothing else sneaks in either")
    func otherCharactersAreRejected() {
        let m = model()
        m.flightNumberDigits = "12 34"
        #expect(m.flightNumberDigits == "1234")
        m.flightNumberDigits = "QF-123 "
        #expect(m.flightNumberDigits == "123")
        m.flightNumberDigits = "✈️7"
        #expect(m.flightNumberDigits == "7")
    }

    /// A field someone is still typing in must stay typable. Filtering must not eat a valid entry
    /// or fight the cursor on every keystroke.
    @Test("ordinary typing is untouched")
    func digitsPassThrough() {
        let m = model()
        for (typed, expected) in [("1", "1"), ("12", "12"), ("123", "123"), ("0060", "0060")] {
            m.flightNumberDigits = typed
            #expect(m.flightNumberDigits == expected)
        }
    }

    /// Clearing the field has to work — a filter that refused to write an empty string would trap
    /// whatever was there.
    @Test("the field can be cleared")
    func canBeCleared() {
        let m = model()
        m.flightNumberDigits = "123"
        m.flightNumberDigits = ""
        #expect(m.flightNumberDigits.isEmpty)
    }

    /// The deep-linked entry, which already filtered and must keep doing so.
    @Test("an initial value is filtered too")
    func initialValueIsFiltered() {
        #expect(model("QF60").flightNumberDigits == "60")
        // Nothing numeric means nothing to search: the flow must not open on a flight-number step
        // with an empty field.
        #expect(model("QF").path.isEmpty)
        #expect(model(nil).flightNumberDigits.isEmpty)
    }
}
