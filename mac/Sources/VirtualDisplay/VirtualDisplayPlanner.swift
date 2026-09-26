import Tab2MacCore

/// The mode the provider selects after the display exists (oriented, logical size).
public struct DisplayModeTarget: Hashable, Sendable, Codable, CustomStringConvertible {
    public var size: PointSize
    public var hiDPI: Bool
    public var refreshRate: Double

    public init(size: PointSize, hiDPI: Bool, refreshRate: Double) {
        self.size = size
        self.hiDPI = hiDPI
        self.refreshRate = refreshRate
    }

    public var description: String { "\(size)\(hiDPI ? "@2x" : "@1x") \(refreshRate)Hz" }
}

/// What to ask the backend for, derived purely from a configuration.
public struct VirtualDisplayPlan: Hashable, Sendable {
    public var descriptor: VirtualDisplayDescriptor
    public var modeSet: VirtualDisplayModeSet
    public var target: DisplayModeTarget
    /// Backing-store size of the target mode (what capture will see).
    public var expectedPixelSize: PixelSize
}

public enum VirtualDisplayPlanner {
    public static func plan(for configuration: VirtualDisplayConfiguration) -> VirtualDisplayPlan {
        let portrait = configuration.orientation == .portrait
        let orient: (PointSize) -> PointSize = { portrait ? $0.swapped : $0 }

        var resolutions: [PointSize] = []
        for size in [configuration.resolution] + configuration.extraResolutions where !resolutions.contains(size) {
            resolutions.append(size)
        }

        // Preferred refresh rate first; always offer 60 Hz so System Settings can fall back.
        let rates = configuration.refreshRate == 60 ? [60.0] : [configuration.refreshRate, 60.0]
        let modes = rates.flatMap { rate in
            resolutions.map { VirtualDisplayModeSpec(size: orient($0), refreshRate: rate) }
        }

        let scale = configuration.hiDPI ? 2 : 1
        // Square bound so the same display can switch orientation without being recreated.
        let maxDimension = resolutions.map { max($0.width, $0.height) * scale }.max() ?? 0

        let descriptor = VirtualDisplayDescriptor(
            name: configuration.name,
            identity: configuration.identity,
            maxPixels: PixelSize(width: maxDimension, height: maxDimension),
            physicalSize: portrait ? configuration.panel.physicalSize.swapped : configuration.panel.physicalSize,
            colorPrimaries: .sRGB
        )
        let target = DisplayModeTarget(size: orient(configuration.resolution), hiDPI: configuration.hiDPI, refreshRate: configuration.refreshRate)
        return VirtualDisplayPlan(
            descriptor: descriptor,
            modeSet: VirtualDisplayModeSet(hiDPI: configuration.hiDPI, modes: modes),
            target: target,
            expectedPixelSize: target.size.pixels(scale: scale)
        )
    }
}
