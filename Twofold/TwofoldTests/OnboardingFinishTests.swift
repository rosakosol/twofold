//
//  OnboardingFinishTests.swift
//  TwofoldTests
//
//  The last steps of onboarding, as AppModel runs them.
//
//    ONB-12  Finishing assumed there was no partner. An inviter who shared a link at "Invite your
//            partner" can be connected by the time they reach the end, and Home opened unpaired.
//    ONB-8   The buttons at the end of the flow ran their work once per tap: each one uploaded the
//            photos again and wrote the questionnaire again.
//
//  Nested under `PendingMemoryDiskTests` because applying the answers goes through the outbox.
//

import Foundation
import Testing
@testable import Twofold

extension PendingMemoryDiskTests {
    @Suite("Finishing onboarding", .serialized)
    @MainActor
    struct OnboardingFinishTests {

        private func pairedState() -> BackendService.CoupleState {
            BackendService.CoupleState(
                couple: Couple(
                    partnerA: Person(name: "Sam", accentColor: Person.palette[1]),
                    partnerB: Person(name: "Alex", accentColor: Person.palette[0]),
                    startedDatingOn: .now
                ),
                trips: [],
                memories: [],
                flights: [],
                subscriptionActive: false,
                viewerSubscriptionActive: false,
                subscriptionTier: nil,
                viewerSubscriptionStore: nil,
                partnerConnectedCelebrationShown: false,
                setupChecklistDismissed: false
            )
        }

        @Test("a partner who connected during onboarding is there when it finishes")
        func finishAdoptsCoupleFormedMidFlow() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            model.backend = FakeCoupleDataBackend()
            model.session.needsOnboarding = true
            let state = pairedState()
            model.fetchCoupleStateOutcome = { .paired(state) }

            await model.finishOnboarding()

            #expect(model.session.hasCouple)
            #expect(model.session.partnerConnected, "Home opened unpaired for a couple that had just connected")
            #expect(model.session.backendCoupleID == state.couple.id)
        }

        @Test("finishing twice at once finishes once")
        func finishCoalesces() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            model.backend = FakeCoupleDataBackend()
            let gate = Gate()
            model.fetchCoupleStateOutcome = {
                await gate.wait()
                return .noCouple
            }

            let first = Task { await model.finishOnboarding() }
            await gate.untilSomeoneArrives()
            let second = Task { await model.finishOnboarding() }
            try? await Task.sleep(for: .milliseconds(100))
            gate.open()
            await first.value
            await second.value

            #expect(gate.arrivals == 1, "a second tap ran the whole finish again")
            #expect(model.session.hasCouple)
        }

        @Test("applying the answers twice at once applies them once")
        func applyCoalesces() async {
            AppModel.clearPersistedAccountState()
            defer { AppModel.clearPersistedAccountState() }
            let model = AppModel()
            model.backend = FakeCoupleDataBackend()
            let gate = Gate()
            model.fetchCoupleStateOutcome = {
                await gate.wait()
                return .noCouple
            }
            let onboarding = OnboardingModel()

            let first = Task { await model.applyOnboardingAccount(onboarding) }
            await gate.untilSomeoneArrives()
            let second = Task { await model.applyOnboardingAccount(onboarding) }
            try? await Task.sleep(for: .milliseconds(100))
            gate.open()
            await first.value
            await second.value

            #expect(gate.arrivals == 1, "a second tap uploaded and wrote everything again")
        }
    }
}
