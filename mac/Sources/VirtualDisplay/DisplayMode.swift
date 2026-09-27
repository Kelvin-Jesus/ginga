import CoreGraphics
import GingaCore

/// A value snapshot of a `CGDisplayMode`.
public struct DisplayModeInfo: Hashable, Sendable, Codable, CustomStringConvertible {
    public var modeID: Int32
    public var size: PointSize
    public var pixelSize: PixelSize
    public var refreshRate: Double
    public var isUsableForDesktopGUI: Bool
    public var ioFlags: UInt32

    public init(modeID: Int32, size: PointSize, pixelSize: PixelSize, refreshRate: Double, isUsableForDesktopGUI: Bool, ioFlags: UInt32) {
        self.modeID = modeID
        self.size = size
        self.pixelSize = pixelSize
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
        self.ioFlags = ioFlags
    }

    public init(_ mode: CGDisplayMode) {
        self.init(
            modeID: mode.ioDisplayModeID,
            size: PointSize(width: mode.width, height: mode.height),
            pixelSize: PixelSize(width: mode.pixelWidth, height: mode.pixelHeight),
            refreshRate: mode.refreshRate,
            isUsableForDesktopGUI: mode.isUsableForDesktopGUI(),
            ioFlags: mode.ioFlags
        )
    }

    public var isHiDPI: Bool { pixelSize.width > size.width }

    /// Same resolution, backing scale and refresh rate (mode IDs and flags may differ between
    /// queries).
    public func isSameMode(as other: DisplayModeInfo) -> Bool {
        size == other.size && pixelSize == other.pixelSize && abs(refreshRate - other.refreshRate) < 0.5
    }
    public var scale: Double { Double(pixelSize.width) / Double(max(size.width, 1)) }
    /// `kDisplayModeNativeFlag` — WindowServer marks the preferred/native mode with it.
    public var isNative: Bool { ioFlags & 0x0200_0000 != 0 }

    public func matches(_ target: DisplayModeTarget, refreshTolerance: Double = 0.5) -> Bool {
        size == target.size && isHiDPI == target.hiDPI && abs(refreshRate - target.refreshRate) <= refreshTolerance
    }

    public var description: String {
        "\(size.width)×\(size.height)pt (\(pixelSize.width)×\(pixelSize.height)px) @\(refreshRate)Hz"
    }
}

public enum DisplayModeMatcher {
    /// The desktop-usable mode with the target's size and scale whose refresh rate is closest.
    public static func bestMatch(for target: DisplayModeTarget, in modes: [DisplayModeInfo]) -> DisplayModeInfo? {
        modes
            .filter { $0.isUsableForDesktopGUI && $0.size == target.size && $0.isHiDPI == target.hiDPI }
            .min { abs($0.refreshRate - target.refreshRate) < abs($1.refreshRate - target.refreshRate) }
    }
}
