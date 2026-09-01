// MurphPlus/DesignSystem/Foundations/MurphShape.swift
// Shape tokens from the Murph+ Design System (tokens/shape.css). Sharp by
// default; borders do the work shadows usually do, and the one shadow that
// exists is a hard screenprint offset, not soft elevation.
import SwiftUI

enum MurphShape {
    static let radiusNone: CGFloat = 0
    static let radiusSm: CGFloat = 4    // chips, inputs
    static let radiusMd: CGFloat = 8    // cards
    static let radiusLg: CGFloat = 14   // sheets, big panels
    static let radiusPill: CGFloat = 999 // primary buttons, segmented control

    static let borderHair: CGFloat = 1
    static let borderStrong: CGFloat = 2

    /// The hard offset "stamp" shadow: a flat ink rectangle, not a blur.
    static let stampOffset = CGSize(width: 3, height: 3)
}

/// Draws Button's `--shadow-stamp`: a flat offset duplicate, not a blurred
/// drop shadow. Content stamps down (offset + press-scale) on press rather
/// than lifting.
struct StampShadow: ViewModifier {
    var color: Color
    var offset: CGSize = MurphShape.stampOffset
    var shape: AnyInsettableShape = AnyInsettableShape(Capsule())

    func body(content: Content) -> some View {
        content.background(
            shape
                .fill(color)
                .offset(x: offset.width, y: offset.height)
        )
    }
}

/// Type-erased insettable shape so callers can pick capsule / rounded rect
/// per component without generic explosion.
struct AnyInsettableShape: Shape {
    private let _path: (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        _path = { rect in shape.path(in: rect) }
    }
    func path(in rect: CGRect) -> Path { _path(rect) }
}
