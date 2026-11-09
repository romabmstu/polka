import CoreGraphics

/// What Polka knows about one connected display, read from `NSScreen` and
/// Core Graphics. Kept free of AppKit so the decisions below can be tested.
public struct DisplayInfo: Equatable, Sendable {
    public var id: UInt32
    public var frame: CGRect
    /// The display built into the Mac (not a monitor on a cable).
    public var isBuiltIn: Bool
    /// `NSScreen.safeAreaInsets.top`.
    public var safeAreaTop: CGFloat
    /// `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`: the parts
    /// of the menu bar on either side of the camera housing.
    public var topLeftArea: CGRect?
    public var topRightArea: CGRect?

    public init(
        id: UInt32, frame: CGRect, isBuiltIn: Bool, safeAreaTop: CGFloat,
        topLeftArea: CGRect?, topRightArea: CGRect?
    ) {
        self.id = id
        self.frame = frame
        self.isBuiltIn = isBuiltIn
        self.safeAreaTop = safeAreaTop
        self.topLeftArea = topLeftArea
        self.topRightArea = topRightArea
    }

    /// Size of the camera housing, or `nil` when this display has none.
    ///
    /// macOS reports the notch in two ways: the safe area and the two
    /// auxiliary areas beside it. While displays are being rearranged, or
    /// after the Mac wakes with a monitor attached, one of them can briefly
    /// read as zero, so either one is enough. A display running at a
    /// resolution that keeps the picture below the camera reports neither,
    /// and correctly gets the menu bar capsule.
    public var notch: CGSize? {
        guard let left = topLeftArea, let right = topRightArea,
            left.width > 0, right.width > 0
        else { return nil }
        let width = frame.width - left.width - right.width
        let height = safeAreaTop > 0 ? safeAreaTop : min(left.height, right.height)
        // Anything else is not a camera housing: a rounding artefact or
        // nonsense from a display in the middle of a mode change.
        guard width >= 40, width <= frame.width / 2, height >= 16, height <= 80 else { return nil }
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}

public enum DisplayGeometry {
    /// The display to use when the user asked for the built-in one: the
    /// display with a notch, otherwise the built-in display (its notch may be
    /// hidden by the chosen resolution, or it is a Mac without one), otherwise
    /// the main display. `displays` is in `NSScreen.screens` order, main first.
    public static func builtIn(in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { $0.notch != nil } ?? displays.first(where: \.isBuiltIn) ?? displays.first
    }

    /// The display under `point`. A point exactly on the edge two displays
    /// share counts for the one whose top edge it is, so pushing the pointer
    /// against the top of a notched display picks that display even when a
    /// monitor sits above it.
    public static func display(at point: CGPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        displays.first { display in
            let frame = display.frame
            return point.x >= frame.minX && point.x < frame.maxX && point.y > frame.minY && point.y <= frame.maxY
        }
    }
}
