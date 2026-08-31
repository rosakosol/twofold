//
//  FlightDocumentTagSheet.swift
//  Twofold
//
//  "What is this?", asked after a file has been picked rather than before.
//
//  Attaching a document used to start by choosing between three cards — Boarding pass, Itinerary,
//  Documents — and only then offered a picker. That put the question in the wrong order (you know
//  what the file is; the app was asking you to commit to a category before it would let you find
//  it), gave the same three pickers three separate entry points, and left everything that wasn't
//  one of the first two labelled with the same generic "Travel documents".
//

import SwiftUI

/// A file that's been picked but not yet uploaded — held while this sheet asks what it is, so
/// cancelling leaves nothing behind.
struct PendingFlightDocument: Identifiable {
    let id = UUID()
    var data: Data
    var contentType: String
    var fileExtension: String
    /// The file's own name, kept as-is for display in the row.
    var originalFilename: String?
    /// What to prefill the custom-name field with — the filename minus its extension, which is
    /// often already what the traveller would have typed ("Spain visa.pdf" → "Spain visa").
    var suggestedName: String?
}

struct FlightDocumentTagSheet: View {
    var suggestedName: String?
    var onCancel: () -> Void
    var onConfirm: (FlightDocumentType, String?) -> Void

    @State private var docType: FlightDocumentType = .boardingPass
    @State private var customName: String = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only `.other` needs a name, and it needs a real one — an empty custom label would put the
    /// document back under the generic heading this exists to avoid.
    private var canConfirm: Bool {
        docType != .other || !trimmedName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("What is this?")
                .font(.headline)

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(FlightDocumentType.allCases, id: \.self) { type in
                    typeRow(type)
                }
            }

            if docType == .other {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Name").font(.caption).foregroundStyle(Theme.subtleInk)
                    TextField("Visa, insurance, hotel booking…", text: $customName)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if canConfirm { confirm() } }
                        .padding(Theme.Spacing.sm)
                        .themedCardBackground(cornerRadius: 12)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .animation(.snappy(duration: 0.2), value: docType)
        .navigationTitle("Add document")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", action: confirm).disabled(!canConfirm).fontWeight(.semibold)
            }
        }
        .onAppear {
            // Prefilled from the filename rather than left blank — for a file called
            // "Spain visa.pdf" this is usually already the answer.
            if customName.isEmpty, let suggestedName { customName = suggestedName }
        }
    }

    private func typeRow(_ type: FlightDocumentType) -> some View {
        Button {
            docType = type
            if type == .other { nameFocused = true }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(type == .other ? "Something else" : type.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                Image(systemName: docType == type ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(docType == type ? Theme.skyBlue : Theme.subtleInk.opacity(0.4))
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .themedCardBackground(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(docType == type ? [.isButton, .isSelected] : .isButton)
    }

    private func confirm() {
        guard canConfirm else { return }
        onConfirm(docType, docType == .other ? trimmedName : nil)
    }
}

#Preview {
    NavigationStack {
        FlightDocumentTagSheet(suggestedName: "Spain visa", onCancel: {}, onConfirm: { _, _ in })
    }
}
