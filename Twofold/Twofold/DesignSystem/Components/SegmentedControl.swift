//
//  SegmentedControl.swift
//  Twofold
//
//  The segmented control of the redesign (docs/TWOFOLD_DESIGN.md, section 5): a `segmentTrack`
//  capsule, a 4pt inset, and the selected segment as a `segmentSelected` pill. Selected text is
//  `textPrimary`, unselected `textSecondary`.
//
//  A replacement for `Picker(.segmented)`, which cannot be restyled this far. It keeps what that
//  control gives VoiceOver: each segment is a button, the chosen one carries the selected trait,
//  and the group says how many there are.
//

import SwiftUI

struct TwofoldSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    /// Read by VoiceOver for the whole control, the way a picker's title is.
    var accessibilityLabel: String = ""
    /// Segments shown but not selectable, the way `.disabled` on a picker row works.
    var disabledValues: Set<Value> = []

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let isSelected = option.value == selection
                let isDisabled = disabledValues.contains(option.value)
                Button {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.segmentSelected)
                                    .shadow(color: Theme.Shadow.color.opacity(0.5), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.45 : 1)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("\(index + 1) of \(options.count)")
            }
        }
        .padding(4)
        .frame(minHeight: 44)
        .background(Theme.segmentTrack, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension TwofoldSegmentedControl where Value: CaseIterable & RawRepresentable, Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    /// For an enum whose raw values are its display labels.
    init(selection: Binding<Value>, accessibilityLabel: String = "") {
        self.init(selection: selection, options: Value.allCases.map { ($0, $0.rawValue) }, accessibilityLabel: accessibilityLabel, disabledValues: [])
    }
}

#Preview {
    @Previewable @State var choice = "Trips"
    TwofoldSegmentedControl(selection: $choice, options: [("Trips", "Trips"), ("Flights", "Flights")])
        .padding()
        .background(Theme.backgroundGradient)
}
