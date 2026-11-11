import SwiftUI

/// How far a drawing is zoomed in and where it has been dragged to.
struct Viewport: Equatable {
    /// 1 fits the whole drawing in the view.
    var zoom: CGFloat = 1
    /// How far the drawing's centre is from the view's centre, in points.
    var offset: CGSize = .zero

    static let zoomRange: ClosedRange<CGFloat> = 1...8

    var isDefault: Bool { self == Viewport() }

    /// The viewport with its zoom in range and the drawing kept on screen:
    /// at zoom 1 it cannot move, and further in it can move just far enough
    /// to bring any part of it to the centre.
    func clamped(in size: CGSize) -> Viewport {
        var next = self
        next.zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let reachX = (next.zoom - 1) * size.width / 2
        let reachY = (next.zoom - 1) * size.height / 2
        next.offset.width = min(max(offset.width, -reachX), reachX)
        next.offset.height = min(max(offset.height, -reachY), reachY)
        return next
    }
}

/// Pinch to zoom and drag to pan. Taps and long presses on the view still
/// work, because a pan only begins once the finger has moved.
struct ViewportGestures: ViewModifier {
    @Binding var viewport: Viewport
    var size: CGSize

    @State private var pinchStart: Viewport?
    @State private var dragStart: Viewport?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchStart ?? viewport
                        pinchStart = base
                        dragStart = nil
                        var next = base
                        next.zoom = min(max(base.zoom * value.magnification, Viewport.zoomRange.lowerBound), Viewport.zoomRange.upperBound)
                        // Keep the point under the fingers where it is.
                        let factor = next.zoom / base.zoom
                        let anchorX = value.startLocation.x - size.width / 2
                        let anchorY = value.startLocation.y - size.height / 2
                        next.offset = CGSize(
                            width: anchorX - (anchorX - base.offset.width) * factor,
                            height: anchorY - (anchorY - base.offset.height) * factor
                        )
                        viewport = next.clamped(in: size)
                    }
                    .onEnded { _ in
                        pinchStart = nil
                        dragStart = nil
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // A pinch moves the first finger too; that is not a pan.
                        guard pinchStart == nil, viewport.zoom > 1 else { return }
                        let base = dragStart ?? viewport
                        dragStart = base
                        var next = base
                        next.offset = CGSize(
                            width: base.offset.width + value.translation.width,
                            height: base.offset.height + value.translation.height
                        )
                        viewport = next.clamped(in: size)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}

extension View {
    func viewportGestures(_ viewport: Binding<Viewport>, in size: CGSize) -> some View {
        modifier(ViewportGestures(viewport: viewport, size: size))
    }
}
