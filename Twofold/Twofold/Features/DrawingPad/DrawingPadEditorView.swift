//
//  DrawingPadEditorView.swift
//  Twofold
//

import SwiftUI

struct DrawingPadEditorView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var elements: [DrawingElement] = []
    @State private var redoStack: [DrawingElement] = []
    @State private var tool: DrawingTool = .pen
    @State private var canvasSize: CGSize = CGSize(width: 600, height: 600)
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DrawingCanvasView(elements: $elements, redoStack: $redoStack, tool: tool)
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
                    }
                    .disabled(elements.isEmpty)
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
        }
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
            content: DrawingCanvasView(elements: .constant(elements), redoStack: .constant([]), tool: .pen)
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
