//
//  NavigationControllerAccessor.swift
//  Twofold
//
//  Lets a SwiftUI view capture a reference to its hosting UINavigationController — for driving
//  real navigation-controller behavior (like popping all the way to root) from deep inside a
//  stack that mixes value-based and plain `NavigationLink(destination:)` pushes, where a bound
//  `NavigationPath` can't reliably reflect every push.
//

import SwiftUI
import UIKit

/// Resolves via `didMove(toParent:)` — the exact UIKit callback that fires the moment this
/// controller is actually attached to its owning `UINavigationController`, rather than guessing
/// at timing with a dispatched async read (which could run before attachment finished, silently
/// leaving the caller with `nil` until some unrelated later re-render happened to try again).
private final class NavigationControllerAccessorViewController: UIViewController {
    var onResolve: ((UINavigationController?) -> Void)?

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        onResolve?(parent?.navigationController)
    }
}

private struct NavigationControllerAccessor: UIViewControllerRepresentable {
    let onResolve: (UINavigationController?) -> Void

    func makeUIViewController(context: Context) -> NavigationControllerAccessorViewController {
        let controller = NavigationControllerAccessorViewController()
        controller.onResolve = onResolve
        return controller
    }

    func updateUIViewController(_ uiViewController: NavigationControllerAccessorViewController, context: Context) {
        uiViewController.onResolve = onResolve
        // Belt-and-suspenders alongside `didMove(toParent:)` — harmless if it re-fires with the
        // same (already-correct) navigation controller.
        if let navigationController = uiViewController.parent?.navigationController {
            onResolve(navigationController)
        }
    }
}

extension View {
    /// Fires as soon as the hosting `UINavigationController` is actually attached — cheap to
    /// just overwrite a stored reference, no dedup needed.
    func capturingNavigationController(_ onResolve: @escaping (UINavigationController?) -> Void) -> some View {
        background(NavigationControllerAccessor(onResolve: onResolve))
    }
}
