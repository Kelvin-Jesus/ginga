import CoreGraphics
import GingaCore
import VirtualDisplay

/// Test doubles shared by VirtualDisplayTests and GingaSessionTests.

/// Simulates WindowServer's view of displays: online list, modes, bounds, arrangement.
@MainActor
public final class FakeDisplayServices: SystemDisplayServices {
    public struct Display {
        public var bounds: CGRect
        public var modes: [DisplayModeInfo]
        public var current: DisplayModeInfo?
        public var mirrorSource: CGDirectDisplayID?

        public init(bounds: CGRect, modes: [DisplayModeInfo], current: DisplayModeInfo?, mirrorSource: CGDirectDisplayID? = nil) {
            self.bounds = bounds
            self.modes = modes
            self.current = current
            self.mirrorSource = mirrorSource
        }
    }

    public static let builtInID: CGDirectDisplayID = 1
    public var displays: [CGDirectDisplayID: Display] = [
        builtInID: Display(bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), modes: [], current: nil)
    ]
    /// When false, created displays never show up online (to exercise timeouts).
    public var displaysComeOnline = true
    /// When true, WindowServer picks the largest mode as default instead of the first listed one.
    public var defaultsToLargestMode = false
    /// Mimics macOS 26 auto-mirroring a new display (e.g. when it is classified as a TV).
    public var autoMirrorSource: CGDirectDisplayID?
    public private(set) var setModeCalls: [DisplayModeInfo] = []
    /// Mimics macOS applying a saved per-combination configuration when a display is added:
    /// these other displays switch to the given mode.
    public var modeChangesWhenDisplayAdded: [CGDirectDisplayID: DisplayModeInfo] = [:]
    public private(set) var setOriginCalls: [CGPoint] = []
    public private(set) var setMirrorCalls: [CGDirectDisplayID?] = []

    public init() {}

    // MARK: Simulation hooks used by FakeBackend

    public func simulateAdd(_ id: CGDirectDisplayID, modeSet: VirtualDisplayModeSet) {
        guard displaysComeOnline else { return }
        let modes = Self.modes(for: modeSet)
        let initial = defaultsToLargestMode ? modes.max { $0.size.width < $1.size.width }! : modes[0]
        let main = displays[Self.builtInID]!.bounds
        displays[id] = Display(
            bounds: CGRect(x: main.maxX, y: 0, width: CGFloat(initial.size.width), height: CGFloat(initial.size.height)),
            modes: modes,
            current: initial,
            mirrorSource: autoMirrorSource
        )
        for (other, mode) in modeChangesWhenDisplayAdded { displays[other]?.current = mode }
    }

    public func simulateReplaceModes(_ id: CGDirectDisplayID, modeSet: VirtualDisplayModeSet) {
        guard var display = displays[id] else { return }
        display.modes = Self.modes(for: modeSet)
        display.current = display.modes[0]
        display.bounds.size = CGSize(width: display.modes[0].size.width, height: display.modes[0].size.height)
        displays[id] = display
    }

    public func simulateRemove(_ id: CGDirectDisplayID) {
        displays[id] = nil
    }

    /// Mimics the user picking a different mode in System Settings.
    public func simulateUserSelectsMode(_ id: CGDirectDisplayID, where predicate: (DisplayModeInfo) -> Bool) {
        guard var display = displays[id], let mode = display.modes.first(where: predicate) else { return }
        display.current = mode
        display.bounds.size = CGSize(width: mode.size.width, height: mode.size.height)
        displays[id] = display
    }

    public static func modes(for modeSet: VirtualDisplayModeSet) -> [DisplayModeInfo] {
        var result: [DisplayModeInfo] = []
        var nextID: Int32 = 100
        for spec in modeSet.modes {
            let scales = modeSet.hiDPI ? [2, 1] : [1]
            for scale in scales {
                result.append(DisplayModeInfo(
                    modeID: nextID,
                    size: spec.size,
                    pixelSize: spec.size.pixels(scale: scale),
                    refreshRate: spec.refreshRate,
                    isUsableForDesktopGUI: true,
                    ioFlags: 0x3
                ))
                nextID += 1
            }
        }
        return result
    }

    // MARK: SystemDisplayServices

    public func onlineDisplayIDs() -> [CGDirectDisplayID] { displays.keys.sorted() }
    public func mainDisplayID() -> CGDirectDisplayID { Self.builtInID }
    public func bounds(of display: CGDirectDisplayID) -> CGRect { displays[display]?.bounds ?? .null }
    public func currentMode(of display: CGDirectDisplayID) -> DisplayModeInfo? { displays[display]?.current }
    public func availableModes(of display: CGDirectDisplayID) -> [DisplayModeInfo] { displays[display]?.modes ?? [] }
    public func mirrorSource(of display: CGDirectDisplayID) -> CGDirectDisplayID? { displays[display]?.mirrorSource }

    public func setMode(_ mode: DisplayModeInfo, of display: CGDirectDisplayID) throws {
        guard var entry = displays[display], entry.modes.contains(mode) else {
            throw DisplayConfigurationError.modeNotFound(mode)
        }
        setModeCalls.append(mode)
        entry.current = mode
        entry.bounds.size = CGSize(width: mode.size.width, height: mode.size.height)
        displays[display] = entry
    }

    public func setMirrorSource(_ source: CGDirectDisplayID?, of display: CGDirectDisplayID) throws {
        guard displays[display] != nil else { throw DisplayConfigurationError.coreGraphics(operation: "mirror", code: 1001) }
        setMirrorCalls.append(source)
        displays[display]!.mirrorSource = source
    }

    public func setOrigin(_ origin: CGPoint, of display: CGDirectDisplayID) throws {
        guard displays[display] != nil else { throw DisplayConfigurationError.coreGraphics(operation: "origin", code: 1001) }
        setOriginCalls.append(origin)
        displays[display]!.bounds.origin = origin
    }
}

@MainActor
public final class FakeBackend: VirtualDisplayBackend {
    public let identifier = "fake"
    public var availabilityResult = BackendAvailability.available(summary: "fake backend")
    public var createError: VirtualDisplayBackendError?
    public var nextDisplayID: CGDirectDisplayID = 77
    public private(set) var createdDescriptors: [VirtualDisplayDescriptor] = []
    public private(set) var appliedModeSets: [VirtualDisplayModeSet] = []
    public private(set) var destroyCount = 0
    public private(set) var displayID: CGDirectDisplayID?
    /// How long a destroyed display stays online (WindowServer lags behind); nil = at once.
    public var removalDelay: Duration?
    private var onTermination: (@MainActor () -> Void)?
    public let system: FakeDisplayServices

    public init(system: FakeDisplayServices) {
        self.system = system
    }

    public func availability() -> BackendAvailability { availabilityResult }

    public func createDisplay(
        _ descriptor: VirtualDisplayDescriptor,
        modes: VirtualDisplayModeSet,
        onTermination: @escaping @MainActor () -> Void
    ) throws -> CGDirectDisplayID {
        if let createError { throw createError }
        guard displayID == nil else { throw VirtualDisplayBackendError.alreadyCreated }
        createdDescriptors.append(descriptor)
        appliedModeSets.append(modes)
        let id = nextDisplayID
        nextDisplayID += 1
        displayID = id
        self.onTermination = onTermination
        system.simulateAdd(id, modeSet: modes)
        return id
    }

    public func setDisplayModes(_ modes: VirtualDisplayModeSet) throws {
        guard let displayID else { throw VirtualDisplayBackendError.noDisplay }
        appliedModeSets.append(modes)
        system.simulateReplaceModes(displayID, modeSet: modes)
    }

    public func destroyDisplay() {
        guard let displayID else { return }
        destroyCount += 1
        if let removalDelay {
            Task { [system] in
                try? await Task.sleep(for: removalDelay)
                system.simulateRemove(displayID)
            }
        } else {
            system.simulateRemove(displayID)
        }
        self.displayID = nil
        onTermination = nil
    }

    /// Mimics WindowServer tearing the display down on its own.
    public func simulateSystemTermination() {
        guard let displayID else { return }
        system.simulateRemove(displayID)
        self.displayID = nil
        onTermination?()
    }
}

@MainActor
public final class FakeReconfigurationSource: DisplayReconfigurationSource {
    private var handler: (@MainActor (CGDirectDisplayID, DisplayChange) -> Void)?
    public private(set) var isObserving = false

    public init() {}

    public func startObserving(_ handler: @escaping @MainActor (CGDirectDisplayID, DisplayChange) -> Void) {
        self.handler = handler
        isObserving = true
    }

    public func stopObserving() {
        handler = nil
        isObserving = false
    }

    public func simulate(_ display: CGDirectDisplayID, _ change: DisplayChange) {
        handler?(display, change)
    }
}
