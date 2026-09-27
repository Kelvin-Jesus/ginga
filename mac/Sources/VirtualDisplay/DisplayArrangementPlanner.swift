import CoreGraphics
import GingaCore

public enum DisplayArrangementPlanner {
    /// Origin in global display coordinates (top-left origin, y grows downward — the
    /// `CGDisplayBounds` space) for a display of `size` placed next to `reference`.
    /// Returns nil for `.automatic`, which leaves placement to macOS.
    ///
    /// If another display already occupies that spot (e.g. the built-in panel sits right of an
    /// external main display), the position slides outward past it instead of overlapping —
    /// otherwise macOS would resolve the overlap by moving the user's other displays.
    public static func origin(
        for arrangement: DisplayArrangement,
        size: PointSize,
        relativeTo reference: CGRect,
        avoiding occupied: [CGRect] = []
    ) -> CGPoint? {
        guard let proposed = adjacentOrigin(for: arrangement, size: size, relativeTo: reference) else { return nil }
        var rect = CGRect(origin: proposed, size: CGSize(width: size.width, height: size.height))
        var moved = true
        while moved {
            moved = false
            for other in occupied {
                let overlap = rect.intersection(other)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                switch arrangement.placement {
                case .right: rect.origin.x = other.maxX
                case .left: rect.origin.x = other.minX - rect.width
                case .above: rect.origin.y = other.minY - rect.height
                case .below: rect.origin.y = other.maxY
                case .automatic: return nil
                }
                moved = true
            }
        }
        return rect.origin
    }

    private static func adjacentOrigin(for arrangement: DisplayArrangement, size: PointSize, relativeTo reference: CGRect) -> CGPoint? {
        let x = Int(reference.minX.rounded())
        let y = Int(reference.minY.rounded())
        let width = Int(reference.width.rounded())
        let height = Int(reference.height.rounded())

        func align(start: Int, length: Int, extent: Int) -> Int {
            switch arrangement.alignment {
            case .start: start
            case .center: start + (length - extent) / 2
            case .end: start + length - extent
            }
        }

        switch arrangement.placement {
        case .automatic:
            return nil
        case .right:
            return CGPoint(x: x + width, y: align(start: y, length: height, extent: size.height))
        case .left:
            return CGPoint(x: x - size.width, y: align(start: y, length: height, extent: size.height))
        case .above:
            return CGPoint(x: align(start: x, length: width, extent: size.width), y: y - size.height)
        case .below:
            return CGPoint(x: align(start: x, length: width, extent: size.width), y: y + height)
        }
    }
}
