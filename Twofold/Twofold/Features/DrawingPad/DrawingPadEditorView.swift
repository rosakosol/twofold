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
    @State private var tool: DrawingTool = .pen
    /// The palette's own black, not `Theme.ink` — see `penColorPalette` for why the pad can't use
    /// appearance-adaptive colours. Starting on `Theme.ink` meant a dark-mode user's very first
    /// stroke was near-white on a white canvas, i.e. invisible until they picked a colour.
    /// Referencing the palette entry rather than repeating the literal also keeps the menu's
    /// selected-checkmark (`penColor == swatch.color`) true on open.
    @State private var penColor: Color = DrawingPadEditorView.defaultPenColor
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 600)
    @State private var isSaving = false
    @State private var backgroundImage: UIImage?
    @State private var hasLoadedBackground = false

    /// A fixed swatch set rather than the system ColorPicker's full spectrum+sliders UI — lets
    /// picking a color be a single tap that auto-closes the menu (ColorPicker's own popover has
    /// no API to dismiss itself on selection, since it supports multi-step interactions).
    ///
    /// Spectrum order top to bottom, then the neutrals: cream, brown, black, white. Reading down
    /// the menu now follows the rainbow instead of the arbitrary order these were added in.
    ///
    /// Literal hex values, deliberately not `Theme.*` tokens. The canvas is `.background(.white)`
    /// in both appearances (see `DrawingCanvasView`) and what gets saved is a PNG, so ink has to be
    /// a fixed colour. The theme tokens are appearance-adaptive: "Black" was `Theme.ink`, which is
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
                DrawingCanvasView(elements: $elements, redoStack: $redoStack, tool: tool, color: penColor, backgroundImage: backgroundImage)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(Theme.Spacing.md)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { canvasSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in canvasSize = newSize }
                        }
                    )

                bottomToolbar
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Your pad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        elements.removeAll()
                        redoStack.removeAll()
                        backgroundImage = nil
                    }
                    .disabled(elements.isEmpty && backgroundImage == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                await loadExistingDrawing()
            }
        }
        .postHogScreenView("Drawing Pad: Editor")
    }

    /// Loads whatever's already saved to the pad so re-opening it continues the drawing instead
    /// of silently starting blank (and `save()` overwriting it with just the new strokes). The
    /// URL is already cache-busted by `uploadDrawingPad`, so a fresh network fetch here is safe.
    private func loadExistingDrawing() async {
        guard !hasLoadedBackground, let url = appModel.myDrawingURL else { return }
        hasLoadedBackground = true
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return }
        backgroundImage = image
    }

    private var bottomToolbar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            toolButton(systemImage: "arrow.uturn.backward", label: "Undo", isDisabled: elements.isEmpty, action: undo)
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
                    .foregroundStyle(isShapeTool ? Theme.skyBlue : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardBackground, in: Circle())
            }
            .accessibilityLabel("Shape")
            .accessibilityValue(isShapeTool ? tool.label : "Pen")

            Menu {
                ForEach(Self.penColorPalette, id: \.name) { swatch in
                    Button {
                        penColor = swatch.color
                    } label: {
                        Label(swatch.name, systemImage: penColor == swatch.color ? "checkmark.circle.fill" : "circle.fill")
                    }
                    .tint(swatch.color)
                }
            } label: {
                Circle()
                    .fill(penColor)
                    .overlay(Circle().strokeBorder(Theme.subtleInk.opacity(0.3), lineWidth: 1))
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .background(Theme.cardBackground, in: Circle())
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
        .background(Theme.cardBackground)
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
                .foregroundStyle(isActive ? Theme.skyBlue : (isDisabled ? Theme.subtleInk.opacity(0.3) : Theme.ink))
                .frame(width: 44, height: 44)
                .background(Theme.cardBackground, in: Circle())
        }
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func undo() {
        guard let last = elements.popLast() else { return }
        redoStack.append(last)
    }

    private func redo() {
        guard let last = redoStack.popLast() else { return }
        elements.append(last)
    }

    private func save() {
        isSaving = true
        let renderer = ImageRenderer(
            content: DrawingCanvasView(elements: .constant(elements), redoStack: .constant([]), tool: .pen, backgroundImage: backgroundImage)
                .frame(width: canvasSize.width, height: canvasSize.height)
        )
        renderer.scale = 2
        Task {
            if let uiImage = renderer.uiImage, let data = uiImage.pngData() {
                await appModel.saveMyDrawing(imageData: data)
            }
            isSaving = false
            dismiss()
        }
    }
}

#Preview {
    DrawingPadEditorView()
        .environment(AppModel())
}
