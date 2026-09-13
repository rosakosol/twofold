//
//  PanelSwapTests.swift
//  TwofoldTests
//
//  Tapping a second pin on the memories map should swap what the panel is showing, not take you
//  somewhere. It used to slide the whole panel away and bring a new one up, which reads as a
//  screen change rather than a change of subject.
//
//  The cause is a difference between two presentation modifiers that looks like a style choice and
//  is not: `sheet(item:)` treats a new item as a new sheet and rebuilds the presentation, where
//  `sheet(isPresented:)` keeps the one that is up and lets its contents change. Measured on the
//  presented view controller's own identity, since that is the thing that does or doesn't survive.
//

import Testing
import SwiftUI
import UIKit
import Observation

@MainActor
struct PanelSwapTests {

    fileprivate struct Selection: Identifiable, Equatable { let id: Int }

    @Observable fileprivate final class Model { var selection: Selection? = Selection(id: 1) }

    /// Presents, swaps the selection, and reports whether the same sheet stayed up.
    private func sheetSurvivesSwap(_ content: @escaping (Model) -> AnyView) async -> (survived: Bool, stillPresented: Bool) {
        // Exclusive for the whole harness, not just the presentation: another suite dismissing on
        // this process's one window mid-measurement is what made the negative control below report
        // that a rebuilt panel had survived. See WindowPresentationTestLock.
        await WindowPresentationTestLock.withExclusiveWindow {
            await sheetSurvivesSwapLocked(content)
        }
    }

    private func sheetSurvivesSwapLocked(_ content: @escaping (Model) -> AnyView) async -> (survived: Bool, stillPresented: Bool) {
        let model = Model()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIHostingController(rootView: content(model))
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()

        await waitUntil(within: 5) { host.presentedViewController != nil }
        let before = host.presentedViewController

        model.selection = Selection(id: 2)
        // Waits for the identity to *change*, rather than sleeping a fixed 1200ms and looking once.
        //
        // That sleep was a guess at how long SwiftUI takes to tear a sheet down and put a new one
        // up, and it was wrong in the one situation that matters: under a full-suite run the
        // rebuild had not happened yet, so `after` was still `before`, and the negative control
        // below — which exists to prove `sheet(item:)` rebuilds — reported that it had survived.
        // Green in isolation, red in a full run, and blaming SwiftUI for it.
        //
        // Polling for the change also makes the two cases cost what they should: a rebuild returns
        // as soon as it lands, and only the survival case spends the whole budget, which is
        // unavoidable — proving something did not happen means waiting long enough to be sure.
        await waitUntil(within: 3) { host.presentedViewController !== before }
        let after = host.presentedViewController

        window.isHidden = true
        return (survived: before != nil && before === after, stillPresented: after != nil)
    }

    /// Polls `condition` until it holds or `seconds` elapse. Wall clock, not a count of naps: a
    /// loaded machine makes each nap longer *and* the thing being waited for slower, so an
    /// iteration count shrinks the budget exactly when it needs to grow.
    private func waitUntil(within seconds: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date.now.addingTimeInterval(seconds)
        while Date.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    /// What the map now uses.
    @Test("a panel bound to isPresented survives a change of subject")
    func isPresentedKeepsThePanel() async {
        let result = await sheetSurvivesSwap { model in
            AnyView(
                Color.clear.sheet(
                    isPresented: Binding(get: { model.selection != nil }, set: { if !$0 { model.selection = nil } })
                ) {
                    Group { if let selection = model.selection { Text("Place \(selection.id)") } }
                        .presentationDetents([.height(220), .fraction(0.98)])
                }
            )
        }
        #expect(result.stillPresented, "the panel closed instead of swapping")
        #expect(result.survived, "the panel was rebuilt — the same sheet should stay up")
    }

    /// The negative control, and the bug. Without it the test above passes for no stated reason —
    /// it would look like sheets simply always survive, and nobody would know why the map is not
    /// using the more natural-looking `item:` form.
    @Test("a panel bound to item is rebuilt instead")
    func itemRebuildsThePanel() async {
        let result = await sheetSurvivesSwap { model in
            AnyView(
                Color.clear.sheet(item: Binding(get: { model.selection }, set: { model.selection = $0 })) { selection in
                    Text("Place \(selection.id)")
                        .presentationDetents([.height(220), .fraction(0.98)])
                }
            )
        }
        #expect(!result.survived, "`sheet(item:)` now keeps its presentation across an item change — the map could use it again")
    }
}
