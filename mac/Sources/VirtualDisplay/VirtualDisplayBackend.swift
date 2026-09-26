import CoreGraphics
import Tab2MacCore

// MARK: - The abstraction the rest of the application depends on

/// Creates and owns one virtual display that WindowServer treats as a real monitor.
///
/// This is the boundary around the most platform-specific (and potentially unstable) part of
/// the system. Implementations may use private API; nothing outside the implementation may.
/// Mode *selection*, arrangement and lifecycle monitoring use public CoreGraphics API and live
/// in `VirtualDisplayProvider`, so a backend only has to create, re-mode and destroy.
///
/// Mapping to the operations in the original brief:
/// - `isAvailable()`      → `availability()`
/// - `createDisplay(cfg)` → `createDisplay(_:modes:onTermination:)` (the provider turns a
///                          configuration into a descriptor + mode set)
/// - `setDisplayMode(m)`  → `setDisplayModes(_:)` here, plus public mode selection in the provider
/// - `getDisplayID()`     → `displayID`
/// - `destroyDisplay()`   → `destroyDisplay()`
/// - `start()` / `stop()` → `VirtualDisplayProvider.start(_:)` / `stop()`
@MainActor
public protocol VirtualDisplayBackend: AnyObject {
    /// Stable name for logs and diagnostics.
    var identifier: String { get }

    /// Whether this backend can work on the running system. Must have no side effects.
    func availability() -> BackendAvailability

    /// Creates the display and advertises `modes` (preferred mode first).
    ///
    /// - Parameter onTermination: invoked if the system tears the display down on its own.
    /// - Returns: the WindowServer-assigned display ID.
    /// - Throws: `VirtualDisplayBackendError`.
    func createDisplay(
        _ descriptor: VirtualDisplayDescriptor,
        modes: VirtualDisplayModeSet,
        onTermination: @escaping @MainActor () -> Void
    ) throws -> CGDirectDisplayID

    /// Replaces the advertised modes of the live display (e.g. orientation or refresh rate
    /// changes) without recreating it, so windows stay where they are.
    /// - Throws: `VirtualDisplayBackendError`.
    func setDisplayModes(_ modes: VirtualDisplayModeSet) throws

    /// The live display, if any.
    var displayID: CGDirectDisplayID? { get }

    /// Removes the display from the system. Idempotent.
    func destroyDisplay()
}

// MARK: - Value types exchanged with backends

/// One advertised mode, in logical points.
public struct VirtualDisplayModeSpec: Hashable, Sendable, CustomStringConvertible {
    public var size: PointSize
    public var refreshRate: Double

    public init(size: PointSize, refreshRate: Double) {
        self.size = size
        self.refreshRate = refreshRate
    }

    public var description: String { "\(size.width)×\(size.height)@\(refreshRate)Hz" }
}

/// The modes a virtual display offers. With `hiDPI`, each mode is rendered at 2× in pixels.
public struct VirtualDisplayModeSet: Hashable, Sendable {
    public var hiDPI: Bool
    /// Preferred mode first.
    public var modes: [VirtualDisplayModeSpec]

    public init(hiDPI: Bool, modes: [VirtualDisplayModeSpec]) {
        self.hiDPI = hiDPI
        self.modes = modes
    }

    /// True when both sets offer the same modes, regardless of order.
    public func hasSameModes(as other: VirtualDisplayModeSet) -> Bool {
        hiDPI == other.hiDPI && Set(modes) == Set(other.modes)
    }
}

public struct ChromaticityPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ColorPrimaries: Hashable, Sendable {
    public var red: ChromaticityPoint
    public var green: ChromaticityPoint
    public var blue: ChromaticityPoint
    public var whitePoint: ChromaticityPoint

    /// ITU-R BT.709 / sRGB primaries with a D65 white point — matches the BT.709 video path.
    public static let sRGB = ColorPrimaries(
        red: ChromaticityPoint(x: 0.640, y: 0.330),
        green: ChromaticityPoint(x: 0.300, y: 0.600),
        blue: ChromaticityPoint(x: 0.150, y: 0.060),
        whitePoint: ChromaticityPoint(x: 0.3127, y: 0.3290)
    )
}

/// Creation-time properties of a virtual display. Changing any of these (other than an
/// orientation swap or shrinking) requires destroying and recreating the display.
public struct VirtualDisplayDescriptor: Hashable, Sendable {
    public var name: String
    public var identity: DisplayIdentity
    /// Upper bound for any backing store the display may use (both orientations).
    public var maxPixels: PixelSize
    public var physicalSize: PhysicalSize
    public var colorPrimaries: ColorPrimaries?

    public init(name: String, identity: DisplayIdentity, maxPixels: PixelSize, physicalSize: PhysicalSize, colorPrimaries: ColorPrimaries?) {
        self.name = name
        self.identity = identity
        self.maxPixels = maxPixels
        self.physicalSize = physicalSize
        self.colorPrimaries = colorPrimaries
    }

    /// Whether moving from `current` (the descriptor the live display was created with) to
    /// `self` needs a new display.
    public func requiresRecreation(comparedTo current: VirtualDisplayDescriptor) -> Bool {
        name != current.name
            || identity != current.identity
            || colorPrimaries != current.colorPrimaries
            || maxPixels.width > current.maxPixels.width
            || maxPixels.height > current.maxPixels.height
            || (physicalSize != current.physicalSize && physicalSize != current.physicalSize.swapped)
    }
}

public enum BackendAvailability: Hashable, Sendable {
    case available(summary: String)
    case unavailable(reason: String, details: [String])

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case .available(let summary): summary
        case .unavailable(let reason, _): reason
        }
    }
}

public enum VirtualDisplayBackendError: Error, Hashable, Sendable, CustomStringConvertible {
    case unavailable(String)
    case alreadyCreated
    case noDisplay
    case creationFailed(String)
    case settingsRejected(String)

    public var description: String {
        switch self {
        case .unavailable(let reason): "backend unavailable: \(reason)"
        case .alreadyCreated: "a display already exists for this backend"
        case .noDisplay: "no display has been created"
        case .creationFailed(let reason): "creation failed: \(reason)"
        case .settingsRejected(let reason): "settings rejected: \(reason)"
        }
    }
}
