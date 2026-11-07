import SwiftUI

/// The outline of the camera housing: concave "shoulders" where it meets the
/// top edge of the screen and rounded corners at the bottom. Both radii
/// animate, so the shape grows smoothly from notch to panel.
struct NotchShape: Shape {
    var shoulderRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulderRadius, bottomRadius) }
        set {
            shoulderRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulderRadius, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height - s)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + s, y: rect.minY + s),
            control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - b))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + s + b, y: rect.maxY),
            control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - b, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - s, y: rect.maxY - b),
            control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
