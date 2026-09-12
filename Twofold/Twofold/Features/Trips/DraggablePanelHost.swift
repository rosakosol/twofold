//
//  DraggablePanelHost.swift
//  Twofold
//
//  Hosts SwiftUI content in a `UIHostingController`-backed `UIView` whose height — and matching
//  rounded-rect + shadow chrome — is driven directly by a `UIPanGestureRecognizer` during an
//  active drag, entirely outside SwiftUI's own state-mutation -> body-recompute -> layout
//  pipeline. `TripsListView`'s travel panel went through several purely-SwiftUI-composed attempts
//  at this same drag (a `DragGesture` mutating `@State` into `.frame(height:)`, containing the
//  relayout's blast radius via `.offset()`, removing the redundant handle gesture entirely) and
//  every one glitched identically on slow/paused drags, while the system's own interactive
//  sheet-dismiss and comparable native apps (not hand-rolled in SwiftUI) track smoothly on the same
//  hardware — pointing at SwiftUI's own diffing/layout pipeline as the bottleneck, not any specific
//  arrangement of it. This escapes that pipeline for the live-tracking phase only: `.changed`
//  mutates the hosting view's `frame` directly (no `@State` touched, so no SwiftUI body
//  re-evaluation or layout pass happens per touch sample); `.ended` hands control back to SwiftUI
//  exactly once, via `onSettle`, so the caller can animate the final snap with `withAnimation` the
//  same way a tap-to-toggle already does — that path has always been glitch-free, since it's a
//  single discrete state change, not hundreds per second.
//
//  Only safe for content that never needs to coexist with something owning its own competing
//  scroll/pan gesture (a real `List`) — see `TripsListView` for how the two stay mutually
//  exclusive (the list-bearing expanded state renders as plain SwiftUI instead, swapped in only
//  once a drag has fully settled).
//

import SwiftUI
import UIKit

/// The heights the travel panel rests at.
///
/// This was a `Bool` — peek or expanded — until the globe underneath needed a state where it
/// isn't half covered. `minimised` is that state: the panel shrinks to its own grab handle, the
/// map gets the whole screen, and dragging the handle back up returns to the other two.
///
/// `Comparable` by height, so "one step shorter" and "one step taller" are expressible; the
/// release logic below uses them for flicks.
enum PanelDetent: Int, CaseIterable, Comparable {
    case minimised = 0
    case peek = 1
    case expanded = 2

    static func < (lhs: PanelDetent, rhs: PanelDetent) -> Bool { lhs.rawValue < rhs.rawValue }

    var shorter: PanelDetent { PanelDetent(rawValue: rawValue - 1) ?? .minimised }
    var taller: PanelDetent { PanelDetent(rawValue: rawValue + 1) ?? .expanded }
}

/// Points per second past which a release counts as a throw rather than a placement. Roughly
/// where a deliberate flick sits, and comfortably above the drift at the end of a slow drag, so
/// releasing gently never skips past a detent you were aiming for.
///
/// At file scope because `Coordinator` is nested inside a generic type, and Swift allows no
/// static stored properties there.
private let panelFlickVelocity: CGFloat = 600

struct DraggablePanelHost<Content: View>: UIViewRepresentable {
    var content: Content
    let minimisedHeight: CGFloat
    let peekHeight: CGFloat
    let expandedHeight: CGFloat
    let cornerRadius: CGFloat
    @Binding var detent: PanelDetent
    @Binding var isDragging: Bool
    /// Fires exactly once per gesture, at release, with the detent it resolved to — the one
    /// moment this hands control back to SwiftUI.
    var onSettle: (PanelDetent) -> Void

    func height(for detent: PanelDetent) -> CGFloat {
        switch detent {
        case .minimised: minimisedHeight
        case .peek: peekHeight
        case .expanded: expandedHeight
        }
    }

    /// The detent whose height is closest to `height` — where a slow drag, released without any
    /// real throw behind it, ends up.
    func nearestDetent(to height: CGFloat) -> PanelDetent {
        PanelDetent.allCases.min {
            abs(self.height(for: $0) - height) < abs(self.height(for: $1) - height)
        } ?? .peek
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.hostingController.rootView = AnyView(content)
        view.cornerRadius = cornerRadius
        view.setHeight(height(for: detent))

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        context.coordinator.hostView = view
        return view
    }

    func updateUIView(_ uiView: HostView, context: Context) {
        context.coordinator.parent = self
        uiView.hostingController.rootView = AnyView(content)
        uiView.cornerRadius = cornerRadius
        // The coordinator owns height live, mid-gesture — this must not fight it (or an unrelated
        // re-render elsewhere in the app, landing mid-drag, would snap the panel back to its
        // pre-drag height for a frame, the exact bug this file exists to avoid).
        guard !context.coordinator.isPanning else { return }
        uiView.setHeight(height(for: detent))
    }

    static func dismantleUIView(_ uiView: HostView, coordinator: Coordinator) {
        coordinator.hostView = nil
    }

    /// Reports whatever height is *currently* showing (live-dragged or settled) rather than
    /// letting SwiftUI's default `UIView` sizing take over — without this, a re-layout pass
    /// triggered by something unrelated mid-drag would ask this view's `sizeThatFits` for a size,
    /// get back the stale pre-drag value (since nothing here calls into SwiftUI's own layout
    /// system to update it), and could reset the live-dragged frame back to that stale value.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: HostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.bounds.width, height: uiView.currentHeight)
    }

    final class HostView: UIView {
        let hostingController = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        private(set) var currentHeight: CGFloat = 0
        var cornerRadius: CGFloat = 0 {
            didSet {
                hostingController.view.layer.cornerRadius = cornerRadius
                hostingController.view.layer.cornerCurve = .continuous
                layoutContent()
            }
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Shadow lives on this view's own layer (which must NOT mask to bounds, or the shadow
            // itself gets clipped away); the rounded-corner clip lives on the hosting content view
            // instead, one layer in — this is the standard split, since a single `CALayer` can't
            // both cast a shadow past its own bounds and clip its content to those same bounds.
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.15
            layer.shadowRadius = 16
            layer.shadowOffset = CGSize(width: 0, height: -4)

            hostingController.view.backgroundColor = .clear
            hostingController.view.clipsToBounds = true
            // Without this, `UIHostingController` adds its own automatic safe-area accounting on
            // top of `expandedHeight` already having `proxy.safeAreaInsets.top` subtracted out in
            // `TripsListView` — the double-counted inset showed up as extra empty space above the
            // drag handle/title, most visible in the expanded (tallest) state.
            hostingController.safeAreaRegions = []
            addSubview(hostingController.view)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setHeight(_ height: CGFloat) {
            currentHeight = height
            var updated = frame
            updated.size.height = height
            frame = updated
            layoutContent()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            layoutContent()
        }

        private func layoutContent() {
            hostingController.view.frame = bounds
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: DraggablePanelHost
        weak var hostView: HostView?
        fileprivate var isPanning = false
        private var restingHeight: CGFloat = 0
        private var startTranslation: CGFloat?

        init(parent: DraggablePanelHost) {
            self.parent = parent
        }

        /// Lets a real tap on the Picker/"+" button/peek card still reach its own `Button` — a
        /// `UIPanGestureRecognizer` only actually claims a touch (transitions out of `.possible`)
        /// once it's tracked several points of real movement, so a genuine tap that never moves
        /// that far simply never fires `handlePan` at all, identical in spirit to the SwiftUI
        /// gesture's old `minimumDistance: 10`.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let hostView, let superview = hostView.superview else { return }
            let translationY = gesture.translation(in: superview).y
            switch gesture.state {
            case .began:
                isPanning = true
                parent.isDragging = true
                restingHeight = parent.height(for: parent.detent)
                startTranslation = translationY

            case .changed:
                let adjusted = translationY - (startTranslation ?? translationY)
                // Clamped to the full range now rather than to the two detents either side of
                // where the drag started, so one gesture can cross from expanded all the way to
                // minimised without stopping at peek on the way.
                let newHeight = min(parent.expandedHeight, max(parent.minimisedHeight, restingHeight - adjusted))
                // Disables the implicit `CALayer` animation `.frame`/`.shadowPath` changes would
                // otherwise pick up — without this, each live update would lag behind by one
                // implicit animation's duration instead of tracking the finger 1:1.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                hostView.setHeight(newHeight)
                CATransaction.commit()

            case .ended, .cancelled:
                // Two detents could be decided by a distance threshold. Three can't: "past 40
                // points" doesn't say *which* of the two remaining ones you meant, and with peek
                // in the middle, the old rule would have made minimised reachable only by
                // dragging all the way through peek and releasing twice.
                //
                // So release resolves the way system sheets do. A throw moves exactly one detent
                // in the direction it was thrown, however far the finger actually got — that is
                // what makes a flick down from peek land on minimised. Anything slower is a
                // placement rather than a throw, and goes to whichever detent it was left nearest.
                let velocity = gesture.velocity(in: superview).y
                let target: PanelDetent
                if velocity > panelFlickVelocity {
                    target = parent.detent.shorter
                } else if velocity < -panelFlickVelocity {
                    target = parent.detent.taller
                } else {
                    target = parent.nearestDetent(to: hostView.currentHeight)
                }
                startTranslation = nil
                isPanning = false
                parent.isDragging = false
                parent.onSettle(target)

            default:
                break
            }
        }
    }
}
