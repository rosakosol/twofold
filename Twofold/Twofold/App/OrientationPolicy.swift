//
//  OrientationPolicy.swift
//  Twofold
//
//  Portrait on every iPhone except where the system puts its bars in a column on the side: closed
//  iPhone Duo stood up as a tent turns the outer display on its side, and the app turns with it.
//
//  Info.plist lists portrait and both landscapes for iPhone so that the system will rotate at all;
//  `PushNotificationDelegate` narrows that per window through this, which keeps every ordinary
//  iPhone exactly as portrait-locked as it was. The inner display ignores supported orientations
//  whatever they say (DUO-1), so in practice the wider mask only changes the closed outer display.
//
//  The signal is the trait the side bar itself follows, `UITraitCollection.verticalBarEdge` (iOS
//  27.1) — the UIKit side of the `toolbarVerticalEdge` the Travel panel and the toolbar buttons
//  read. It is unspecified on hardware that never has a vertical bar, so no device model is
//  involved. A `UIHingeInteraction` looked like the natural signal, but the iPhone Duo simulator
//  never delivers it an update, closed or otherwise.
//

import SwiftUI
import UIKit

enum OrientationPolicy {
    /// The orientations a window may take.
    static func supportedOrientations(hasVerticalBar: Bool) -> UIInterfaceOrientationMask {
        hasVerticalBar ? .allButUpsideDown : .portrait
    }

    /// What the observer last saw. Read by the app delegate, which UIKit asks whenever it rotates
    /// or is told the answer may have changed.
    @MainActor static var hasVerticalBar = false

    @MainActor static var current: UIInterfaceOrientationMask {
        supportedOrientations(hasVerticalBar: hasVerticalBar)
    }
}

/// Watches the window it is placed in for a vertical bar and updates `OrientationPolicy`. Placed
/// once, behind `RootView`.
struct VerticalBarObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> ObserverView {
        ObserverView()
    }

    func updateUIView(_ uiView: ObserverView, context: Context) {}

    final class ObserverView: UIView {
        private var registered = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard #available(iOS 27.1, *) else { return }
            if !registered {
                registered = true
                registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (view: ObserverView, _: UITraitCollection) in
                    view.update()
                }
            }
            update()
        }

        @available(iOS 27.1, *)
        private func update() {
            guard let window else { return }
            let hasVerticalBar = window.traitCollection.verticalBarEdge != .unspecified
            guard hasVerticalBar != OrientationPolicy.hasVerticalBar else { return }
            OrientationPolicy.hasVerticalBar = hasVerticalBar
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
