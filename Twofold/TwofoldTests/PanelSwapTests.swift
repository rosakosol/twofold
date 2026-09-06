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
        let model = Model()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let host = UIHostingController(rootView: content(model))
        window.rootViewController = host
        window.isHidden = false
        window.makeKeyAndVisible()

        for _ in 0..<40 where host.presentedViewController == nil {
            try? await Task.sleep(for: .milliseconds(50))
        }
        let before = host.presentedViewController

        model.selection = Selection(id: 2)
        try? await Task.sleep(for: .milliseconds(1200))
        let after = host.presentedViewController

        window.isHidden = true
        return (survived: before != nil && before === after, stillPresented: after != nil)
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
