//
//  DrawingPadEditorView.swift
//  Twofold
//

import PostHog
import SwiftUI

struct DrawingPadEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var elements: [DrawingElement] = []
    @State private var redoStack: [DrawingElement] = []
    /// What each Clear wiped, newest last, so Undo can bring it back. Undo first takes back anything
    /// drawn since the clear; once that's gone, the next Undo restores the pad as it was.
    @State private var clearedPads: [ClearedPad] = []

    private struct ClearedPad {
        let elements: [DrawingElement]
        let redoStack: [DrawingElement]
        let backgroundImage: UIImage?
    }
    @State private var tool: DrawingTool = .pen
    /// The palette's own black, not `Theme.textPrimary` — see `penColorPalette` for why the pad can't use
    /// appearance-adaptive colours. Starting on `Theme.textPrimary` meant a dark-mode user's very first
    /// stroke was near-white on a white canvas, i.e. invisible until they picked a colour.
    /// Referencing the palette entry rather than repeating the literal also keeps the menu's
    /// selected-checkmark (`penColor == swatch.color`) true on open.
    @State private var penColor: Color = DrawingPadEditorView.defaultPenColor
    @State private var isSaving = false
    @State private var backgroundImage: UIImage?
    @State private var hasLoadedBackground = false
    /// Until the saved pad has loaded, Save is off: saving earlier would upload the new strokes on
    /// a blank background over the drawing that was still on its way.
    @State private var isLoadingBackground = true
    /// The saved pad couldn't be fetched, so whatever's on the canvas isn't the whole drawing.
    @State private var backgroundLoadFailed = false
    @State private var confirmingReplace = false
    @State private var saveFailed = false
    /// The canvas as it stands, saved or not, while the share sheet is up.
    @State private var sharedCanvas: UIImage?

    /// A fixed swatch set rather than the system ColorPicker's full spectrum+sliders UI — lets
    /// picking a color be a single tap that auto-closes the menu (ColorPicker's own popover has
    /// no API to dismiss itself on selection, since it supports multi-step interactions).
    ///
    /// Spectrum order top to bottom, then the neutrals: cream, brown, black, white. Reading down
    /// the menu now follows the rainbow instead of the arbitrary order these were added in.
    ///
    /// Literal hex values, deliberately not `Theme.*` tokens. The canvas is `.background(.white)`
    /// in both appearances (see `DrawingCanvasView`) and what gets saved is a PNG, so ink has to be
    /// a fixed colour. The theme tokens are appearance-adaptive: "Black" was `Theme.textPrimary`, which is
    /// `#F3F7FA` in dark mode — near-white ink on a permanently white canvas, i.e. invisible. Red,
    /// blue and green were washing out the same way.
    private static let penColorPalette: [(name: String, color: Color)] = [
        ("Red", Color(hex: "E5322D")),
        ("Orange", Color(hex: "F07C1F")),
        ("Yellow", Color(hex: "F2B705")),
        ("Green", Color(hex: "2FA84F")),
        ("Blue", Color(hex: "2F6FE0")),
        ("Indigo", Color(hex: "4436B8")),
        ("Violet", Color(hex: "8B3FC7")),
        ("Pink", Color(hex: "E0489A")),
        ("Cream", Color(hex: "F0E2C0")),
        ("Brown", Color(hex: "8A5A2B")),
        ("Black", defaultPenColor),
        ("White", Color(hex: "FFFFFF")),
    ]

    /// Black — what the pad opens on.
    private static let defaultPenColor = Color(hex: "1A1A1A")

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if backgroundLoadFailed {
                    loadFailedNotice
                }

                // The canvas keeps its own fixed shape (see `DrawingCanvasGeometry`), so it is
                // usually narrower or shorter than the room here. The flexible frame centres it in
                // that room and keeps the toolbar at the bottom, rather than letting the stack
                // shrink to the canvas and float the toolbar up the screen.
                DrawingCanvasView(
                    elements: $elements,
                    redoStack: $redoStack,
                    tool: tool,
                    color: penColor,
                    backgroundImage: backgroundImage
                )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                bottomToolbar
            }
            .background(ScreenBackground())
            .navigationTitle("Your pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sharedCanvas = renderCanvas()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share drawing")
                    .disabled(elements.isEmpty && backgroundImage == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        clearedPads.append(ClearedPad(elements: elements, redoStack: redoStack, backgroundImage: backgroundImage))
                        elements.removeAll()
                        redoStack.removeAll()
                        backgroundImage = nil
                    }
                    // Off while loading too: a Clear before the saved pad arrives would be undone
                    // by its arrival, or (undone itself) restore a snapshot that never had it.
                    .disabled((elements.isEmpty && backgroundImage == nil) || isLoadingBackground)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if backgroundLoadFailed {
                            confirmingReplace = true
                        } else {
                            save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || isLoadingBackground)
                }
            }
            .task {
                await loadExistingDrawing()
            }
            .confirmationDialog(
                "Replace your saved drawing?",
                isPresented: $confirmingReplace,
                titleVisibility: .visible
            ) {
                Button("Replace drawing", role: .destructive, action: save)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your saved drawing couldn't be loaded, so saving now replaces it with only what's on this pad.")
            }
            // Stays open on failure, strokes and all. It used to dismiss whatever happened, which
            // threw the drawing away without a word.
            .alert("Couldn't save your drawing", isPresented: $saveFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your drawing is still here. Check your connection and try saving again.")
            }
        }
        .sheet(isPresented: Binding(get: { sharedCanvas != nil }, set: { if !$0 { sharedCanvas = nil } })) {
            if let sharedCanvas {
                DrawingShareSheet(pads: [.init(person: appModel.currentUser, url: nil, image: sharedCanvas)])
            }
        }
        .postHogScreenView("Drawing Pad: Editor")
    }

    /// Loads whatever's already saved to the pad so re-opening it continues the drawing instead
    /// of silently starting blank (and `save()` overwriting it with just the new strokes). A
    /// failure is reported rather than shown as an empty pad — see `DrawingPadLoader`.
    private func loadExistingDrawing() async {
        guard !hasLoadedBackground else { return }
        hasLoadedBackground = true
        isLoadingBackground = true
        defer { isLoadingBackground = false }
        switch await DrawingPadLoader.load(appModel.myDrawingURL) {
        case .blank:
            backgroundLoadFailed = false
        case .loaded(let image):
            backgroundImage = image
            backgroundLoadFailed = false
        case .failed:
            backgroundLoadFailed = true
        }
    }

    private var loadFailedNotice: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent)
            Text("Couldn't load your saved drawing.")
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Try again") {
                hasLoadedBackground = false
                Task { await loadExistingDrawing() }
            }
            .font(.footnote.weight(.semibold))
            .disabled(isLoadingBackground)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
    }

    private var bottomToolbar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            toolButton(systemImage: "arrow.uturn.backward", label: "Undo", isDisabled: elements.isEmpty && clearedPads.isEmpty, action: undo)
            toolButton(systemImage: "arrow.uturn.forward", label: "Redo", isDisabled: redoStack.isEmpty, action: redo)
            toolButton(systemImage: "eraser", label: "Eraser", isActive: tool == .eraser) { tool = .eraser }

            Menu {
                ForEach([DrawingTool.pen, .rectangle, .ellipse, .line], id: \.self) { option in
                    Button {
                        tool = option
                    } label: {
                        Label(option.label, systemImage: option.systemImage)
                    }
                }
            } label: {
                Image(systemName: shapesIcon)
                    .font(.title2)
                    .foregroundStyle(isShapeTool ? Theme.accent : Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .accessibilityLabel("Shape")
            .accessibilityValue(isShapeTool ? tool.label : "Pen")

            Menu {
                ForEach(Self.penColorPalette, id: \.name) { swatch in
                    Button {
                        penColor = swatch.color
                        // Picking a colour means drawing with it. Left on the eraser, the next
                        // stroke rubbed out instead, in no colour at all. A shape tool stays, since
                        // the colour is for it too.
                        if tool == .eraser { tool = .pen }
                    } label: {
                        Label(swatch.name, systemImage: penColor == swatch.color ? "checkmark.circle.fill" : "circle.fill")
                    }
                    .tint(swatch.color)
                }
            } label: {
                Circle()
                    .fill(penColor)
                    .overlay(Circle().strokeBorder(Theme.textSecondary.opacity(0.3), lineWidth: 1))
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            // Without this the spectrum comes out upside down. A menu defaults to `.priority`
            // order, which puts the first declared item nearest the button — and this button is in
            // the bottom toolbar, so the menu opens upward and renders the list bottom-to-top.
            // `.fixed` shows it in declared order whichever way the menu happens to open.
            .menuOrder(.fixed)
            .accessibilityLabel("Pen color")
            .accessibilityValue(Self.penColorPalette.first { $0.color == penColor }?.name ?? "Custom")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var isShapeTool: Bool {
        [.rectangle, .ellipse, .line].contains(tool)
    }

    private var shapesIcon: String {
        isShapeTool ? tool.systemImage : "square.on.circle"
    }

    private func toolButton(systemImage: String, label: String, isDisabled: Bool = false, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isActive ? Theme.accent : (isDisabled ? Theme.textSecondary.opacity(0.3) : Theme.textPrimary))
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: Circle())
        }
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func undo() {
        if let last = elements.popLast() {
            redoStack.append(last)
        } else if let cleared = clearedPads.popLast() {
            elements = cleared.elements
            redoStack = cleared.redoStack
            backgroundImage = cleared.backgroundImage
        }
    }

    private func redo() {
        guard let last = redoStack.popLast() else { return }
        elements.append(last)
    }

    /// The canvas flattened to an image, the same way it is saved.
    private func renderCanvas() -> UIImage? {
        DrawingCanvasView.renderedImage(elements: elements, backgroundImage: backgroundImage)
    }

    private func save() {
        isSaving = true
        let image = renderCanvas()
        Task {
            var saved = false
            if let uiImage = image, let data = uiImage.pngData() {
                saved = await appModel.saveMyDrawing(imageData: data)
            }
            isSaving = false
            if saved {
                dismiss()
            } else {
                saveFailed = true
            }
        }
    }
}

#Preview {
    DrawingPadEditorView()
        .environment(AppModel())
}
