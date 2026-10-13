import SwiftUI
import PencilKit

public struct WritingCanvasView: UIViewRepresentable {
    @Binding public var canvasView: PKCanvasView
    public let strokeColor: Color
    public let lineWidth: CGFloat
    public var onDrawingChanged: (() -> Void)? = nil

    public init(
        canvasView: Binding<PKCanvasView>,
        strokeColor: Color,
        lineWidth: CGFloat = 8.0,
        onDrawingChanged: (() -> Void)? = nil
    ) {
        self._canvasView = canvasView
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.onDrawingChanged = onDrawingChanged
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: lineWidth)
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = context.coordinator
        return canvasView
    }

    public func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: lineWidth)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: WritingCanvasView

        init(_ parent: WritingCanvasView) {
            self.parent = parent
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
}