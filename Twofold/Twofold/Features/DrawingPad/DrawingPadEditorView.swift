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
    @State private var penColor: Color = Theme.ink
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 600)
    @State private var isSaving = false
    @State private var backgroundImage: UIImage?
    @State private var hasLoadedBackground = false

    /// A fixed swatch set rather than the system ColorPicker's full spectrum+sliders UI — lets
    /// picking a color be a single tap that auto-closes the menu (ColorPicker's own popover has
    /// no API to dismiss itself on selection, since it supports multi-step interactions).
    private static let penColorPalette: [(name: String, color: Color)] = [
        ("Black", Theme.ink),
        ("Red", Theme.heartRed),
        ("Blue", Theme.skyBlue),
        ("Green", Theme.leafGreen),
        ("Orange", .orange),
        ("Purple", .purple),
        ("Pink", .pink),
        ("Brown", .brown),
    ]

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
            toolButton(systemImage: "arrow.uturn.backward", isDisabled: elements.isEmpty, action: undo)
            toolButton(systemImage: "arrow.uturn.forward", isDisabled: redoStack.isEmpty, action: redo)
            toolButton(systemImage: "eraser", isActive: tool == .eraser) { tool = .eraser }

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
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(.white)
    }

    private var isShapeTool: Bool {
        [.rectangle, .ellipse, .line].contains(tool)
    }

    private var shapesIcon: String {
        isShapeTool ? tool.systemImage : "square.on.circle"
    }

    private func toolButton(systemImage: String, isDisabled: Bool = false, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(isActive ? Theme.skyBlue : (isDisabled ? Theme.subtleInk.opacity(0.3) : Theme.ink))
                .frame(width: 44, height: 44)
                .background(Theme.cardBackground, in: Circle())
        }
        .disabled(isDisabled)
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
