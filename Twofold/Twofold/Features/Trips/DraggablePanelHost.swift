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

struct DraggablePanelHost<Content: View>: UIViewRepresentable {
    var content: Content
    let peekHeight: CGFloat
    let expandedHeight: CGFloat
    let cornerRadius: CGFloat
    @Binding var isExpanded: Bool
    @Binding var isDragging: Bool
    /// Fires exactly once per gesture, at release, with the direction it resolved to — the one
    /// moment this hands control back to SwiftUI.
    var onSettle: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.hostingController.rootView = AnyView(content)
        view.cornerRadius = cornerRadius
        view.setHeight(isExpanded ? expandedHeight : peekHeight)

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
        uiView.setHeight(isExpanded ? expandedHeight : peekHeight)
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
        private var minOffset: CGFloat = 0
        private var maxOffset: CGFloat = 0
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
                restingHeight = parent.isExpanded ? parent.expandedHeight : parent.peekHeight
                minOffset = restingHeight - parent.expandedHeight
                maxOffset = restingHeight - parent.peekHeight
                startTranslation = translationY

            case .changed:
                let adjusted = translationY - (startTranslation ?? translationY)
                let dragOffset = min(max(adjusted, minOffset), maxOffset)
                let newHeight = min(parent.expandedHeight, max(parent.peekHeight, restingHeight - dragOffset))
                // Disables the implicit `CALayer` animation `.frame`/`.shadowPath` changes would
                // otherwise pick up — without this, each live update would lag behind by one
                // implicit animation's duration instead of tracking the finger 1:1.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                hostView.setHeight(newHeight)
                CATransaction.commit()

            case .ended, .cancelled:
                // Baseline-adjusted the same way `.changed` is — using the raw, unadjusted
                // `gesture.translation` here (as an earlier version of this did) silently made
                // the commit threshold a few points more sensitive than what `.changed` had
                // actually been live-tracking, since the "already traveled before `.began`
                // fired" baseline was still baked into it.
                let translation = translationY - (startTranslation ?? translationY)
                var newExpanded = parent.isExpanded
                if translation < -40 {
                    newExpanded = true
                } else if translation > 40 {
                    newExpanded = false
                }
                startTranslation = nil
                isPanning = false
                parent.isDragging = false
                parent.onSettle(newExpanded)

            default:
                break
            }
        }
    }
}
