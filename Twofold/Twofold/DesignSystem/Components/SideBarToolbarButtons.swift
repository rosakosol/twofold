//
//  SideBarToolbarButtons.swift
//  Twofold
//
//  Toolbar Cancel / Close / Done / Save: words on a phone, symbols in iPhone Duo's side bar.
//
//  On iPhone Duo the system moves toolbar items into a vertical bar on the side — the outer
//  display, and the inner one opened like a book — but only items with both a title and a symbol.
//  A text-only button stays behind in a strip across the top (DUO-6). Giving every Cancel and Save
//  an xmark or a checkmark fixed that, and also turned them into icons on every other iPhone,
//  which is not what the owner wants there: on a phone with its bars along the top and bottom,
//  these stay the words they always were, in the places they always were.
//
//  So the decision is made here, once, from the same signal the Travel panel uses to know the
//  bars are on the side: SwiftUI's `toolbarVerticalEdge`, non-nil exactly when this screen's bars
//  are a vertical column. Not a device model — the inner display held in portrait has horizontal
//  bars, and a centred sheet there does too, and both get the words.
//
//  VoiceOver reads the same title either way.
//

import SwiftUI

/// A toolbar button that is a titled symbol where the toolbar is a side bar, and its title alone
/// everywhere else.
struct BarButton: View {
    private let title: Text
    private let systemImage: String
    private let role: ButtonRole?
    /// Semibold text on a phone — how Save, Add and Use photo were always drawn there.
    private let emphasized: Bool
    private let action: () -> Void

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        role: ButtonRole? = nil,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.role = role
        self.emphasized = emphasized
        self.action = action
    }

    /// For titles that arrive as data (Add Flight's "Cancel" / "Back" is the flow's to choose).
    init(
        verbatim title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.role = role
        self.emphasized = emphasized
        self.action = action
    }

    /// Cancel, Close, Not now.
    static func close(_ title: LocalizedStringKey, action: @escaping () -> Void) -> BarButton {
        BarButton(title, systemImage: "xmark", role: .close, action: action)
    }

    /// Done, Save, Add, Use photo.
    static func confirm(_ title: LocalizedStringKey, emphasized: Bool = true, action: @escaping () -> Void) -> BarButton {
        BarButton(title, systemImage: "checkmark", role: .confirm, emphasized: emphasized, action: action)
    }

    var body: some View {
        SideBarReader { inSideBar in
            if inSideBar {
                Button(role: role, action: action) {
                    Label { title } icon: { Image(systemName: systemImage) }
                }
            } else {
                // The phone's button as it was before DUO-6: no close/confirm role (on iOS 26
                // those draw the glass xmark and checkmark), only a destructive one where the
                // button really is.
                Button(role: role == .destructive ? .destructive : nil, action: action) {
                    title.fontWeight(emphasized ? .semibold : nil)
                }
            }
        }
    }
}

/// A Cancel / Close toolbar item: `.cancellationAction` in a side bar, which is the top of the
/// column, and wherever the screen always had it on a phone — leading for most, trailing for the
/// gate screens.
struct CloseToolbarItem: ToolbarContent {
    private let title: LocalizedStringKey?
    private let verbatimTitle: String?
    private let phonePlacement: ToolbarItemPlacement
    private let action: () -> Void

    init(_ title: LocalizedStringKey, phonePlacement: ToolbarItemPlacement = .topBarLeading, action: @escaping () -> Void) {
        self.title = title
        self.verbatimTitle = nil
        self.phonePlacement = phonePlacement
        self.action = action
    }

    init(verbatim title: String, phonePlacement: ToolbarItemPlacement = .topBarLeading, action: @escaping () -> Void) {
        self.title = nil
        self.verbatimTitle = title
        self.phonePlacement = phonePlacement
        self.action = action
    }

    private var button: BarButton {
        if let title {
            BarButton(title, systemImage: "xmark", role: .close, action: action)
        } else {
            BarButton(verbatim: verbatimTitle ?? "", systemImage: "xmark", role: .close, action: action)
        }
    }

    var body: some ToolbarContent {
        if #available(iOS 27.1, *) {
            SideBarAwareCloseItem(button: button, phonePlacement: phonePlacement)
        } else {
            ToolbarItem(placement: phonePlacement) { button }
        }
    }
}

@available(iOS 27.1, *)
private struct SideBarAwareCloseItem: ToolbarContent {
    let button: BarButton
    let phonePlacement: ToolbarItemPlacement
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge

    var body: some ToolbarContent {
        if toolbarVerticalEdge != nil {
            ToolbarItem(placement: .cancellationAction) { button }
        } else {
            ToolbarItem(placement: phonePlacement) { button }
        }
    }
}

/// Whether this view's toolbar is a vertical side bar. `toolbarVerticalEdge` exists from iOS 27.1
/// and this app still runs on 26, where the bars are always horizontal.
private struct SideBarReader<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        if #available(iOS 27.1, *) {
            Reader(content: content)
        } else {
            content(false)
        }
    }

    @available(iOS 27.1, *)
    private struct Reader: View {
        @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
        let content: (Bool) -> Content

        var body: some View {
            content(toolbarVerticalEdge != nil)
        }
    }
}
