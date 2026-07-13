//
//  InteractivePopGestureDisabler.swift
//  Twofold
//
//  `.navigationBarBackButtonHidden(true)` only hides the button — the edge-swipe-to-go-back
//  gesture stays live and would otherwise let someone bypass a custom back button's logic (e.g.
//  a leave-confirmation) entirely. This reaches into the hosting UINavigationController to
//  disable that gesture directly.
//

import SwiftUI
import UIKit

private struct InteractivePopGestureDisabler: UIViewControllerRepresentable {
    var isDisabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.parent?.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isDisabled
        }
    }
}

extension View {
    func interactivePopGestureDisabled(_ isDisabled: Bool = true) -> some View {
        background(InteractivePopGestureDisabler(isDisabled: isDisabled))
    }
}
