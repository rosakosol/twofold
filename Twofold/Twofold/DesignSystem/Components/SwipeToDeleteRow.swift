//
//  SwipeToDeleteRow.swift
//  Twofold
//
//  Swipe-to-delete for a row that isn't in a `List`.
//
//  `.swipeActions` only exists on `List`, and some rows can't be in one — the flight documents
//  live inside `FlightTrackingView`'s own `ScrollView`, and nesting a `List` there would mean a
//  scroll view inside a scroll view with a height that has to be guessed. So the gesture is
//  hand-rolled, with the two things that usually go wrong when it is:
//
//  1. It must not fight the vertical scroll. The drag is ignored until it has travelled far enough
//     to be unambiguous *and* is clearly more horizontal than vertical — so a finger moving down
//     the page scrolls the page, every time, and never leaves half-open rows in its wake.
//  2. It must not be the only way to delete. A swipe is invisible to VoiceOver and undiscoverable
//     for anyone who doesn't think to try it, so the same action is on a context menu and the
//     revealed button carries a real accessibility label.
//

import SwiftUI

struct SwipeToDeleteRow<Content: View>: View {
    var onDelete: () -> Void
    var accessibilityLabel: String
    @ViewBuilder var content: Content

    /// How far the row sits open when the delete button is showing.
    private let revealWidth: CGFloat = 76
    /// How far a drag must travel before it counts as a swipe rather than a wobble on the way to
    /// scrolling. Below this the gesture does nothing at all.
    private let activationThreshold: CGFloat = 12

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @GestureState private var dragWidth: CGFloat = 0

    private var currentOffset: CGFloat {
        min(0, max(-revealWidth, offset + dragWidth))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton
                // Fades in with the reveal rather than sitting fully drawn behind an unmoved row,
                // where it shows through the row's own rounded corners.
                .opacity(Double(-currentOffset / revealWidth))

            // No background of its own — callers hand in a row that already carries one (the
            // document rows use `themedCardBackground`), and it needs to be opaque so the delete
            // button stays hidden behind the row until it's actually slid aside.
            content
                .offset(x: currentOffset)
                .gesture(swipe)
        }
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .animation(.snappy(duration: 0.22), value: currentOffset)
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            close()
            onDelete()
        } label: {
            Image(systemName: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: revealWidth, height: 36)
                .background(Theme.heartRed, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        // Unreachable while closed, so a tap near the row's trailing edge doesn't delete something
        // the row was still covering.
        .allowsHitTesting(isOpen)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: activationThreshold)
            .updating($dragWidth) { value, state, _ in
                // Vertical intent wins outright: this is the check that keeps the page scrolling
                // normally when a finger passes over a row on its way down.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Predicted end, not the raw position, so a quick flick opens the row the way a
                // slow deliberate drag past halfway does.
                let projected = offset + value.predictedEndTranslation.width
                setOpen(projected < -revealWidth / 2)
            }
    }

    private func setOpen(_ open: Bool) {
        isOpen = open
        offset = open ? -revealWidth : 0
    }

    private func close() { setOpen(false) }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(["Boarding pass.pdf", "Spain visa.pdf"], id: \.self) { name in
            SwipeToDeleteRow(onDelete: {}, accessibilityLabel: "Delete \(name)") {
                HStack {
                    Text(name).font(.caption)
                    Spacer()
                }
                .padding(8)
            }
        }
    }
    .padding()
    .background(Theme.backgroundGradient)
}
