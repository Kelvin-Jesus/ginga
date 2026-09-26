import CoreGraphics
import Dispatch

/// What changed about a display, decoded from `CGDisplayChangeSummaryFlags`.
public struct DisplayChange: OptionSet, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let added = DisplayChange(rawValue: 1 << 0)
    public static let removed = DisplayChange(rawValue: 1 << 1)
    public static let modeChanged = DisplayChange(rawValue: 1 << 2)
    public static let moved = DisplayChange(rawValue: 1 << 3)
    public static let becameMain = DisplayChange(rawValue: 1 << 4)
    public static let enabled = DisplayChange(rawValue: 1 << 5)
    public static let disabled = DisplayChange(rawValue: 1 << 6)
    public static let mirrored = DisplayChange(rawValue: 1 << 7)
    public static let unmirrored = DisplayChange(rawValue: 1 << 8)
    public static let desktopShapeChanged = DisplayChange(rawValue: 1 << 9)

    private static let names: [(DisplayChange, String)] = [
        (.added, "added"), (.removed, "removed"), (.modeChanged, "modeChanged"), (.moved, "moved"),
        (.becameMain, "becameMain"), (.enabled, "enabled"), (.disabled, "disabled"),
        (.mirrored, "mirrored"), (.unmirrored, "unmirrored"), (.desktopShapeChanged, "desktopShapeChanged"),
    ]

    /// Decodes a reconfiguration callback. The "begin configuration" phase announces changes that
    /// have not happened yet and is reported as empty; the completion callback follows.
    public init(_ flags: CGDisplayChangeSummaryFlags) {
        guard !flags.contains(.beginConfigurationFlag) else {
            self = []
            return
        }
        let mapping: [(CGDisplayChangeSummaryFlags, DisplayChange)] = [
            (.addFlag, .added), (.removeFlag, .removed), (.setModeFlag, .modeChanged), (.movedFlag, .moved),
            (.setMainFlag, .becameMain), (.enabledFlag, .enabled), (.disabledFlag, .disabled),
            (.mirrorFlag, .mirrored), (.unMirrorFlag, .unmirrored), (.desktopShapeChangedFlag, .desktopShapeChanged),
        ]
        var change: DisplayChange = []
        for (flag, value) in mapping where flags.contains(flag) {
            change.insert(value)
        }
        self = change
    }

    public var description: String {
        Self.names.filter { contains($0.0) }.map(\.1).joined(separator: ",")
    }
}

/// Source of display reconfiguration notifications (protocol so tests can inject events).
@MainActor
public protocol DisplayReconfigurationSource: AnyObject {
    func startObserving(_ handler: @escaping @MainActor (CGDirectDisplayID, DisplayChange) -> Void)
    func stopObserving()
}

/// Wraps `CGDisplayRegisterReconfigurationCallback`. Call `stopObserving()` before releasing.
@MainActor
public final class DisplayReconfigurationMonitor: DisplayReconfigurationSource {
    private var handler: (@MainActor (CGDirectDisplayID, DisplayChange) -> Void)?
    private var isRegistered = false

    public init() {}

    public func startObserving(_ handler: @escaping @MainActor (CGDirectDisplayID, DisplayChange) -> Void) {
        self.handler = handler
        guard !isRegistered else { return }
        isRegistered = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque()) == .success
    }

    public func stopObserving() {
        handler = nil
        guard isRegistered else { return }
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, Unmanaged.passUnretained(self).toOpaque())
        isRegistered = false
    }

    fileprivate func deliver(_ display: CGDirectDisplayID, _ change: DisplayChange) {
        handler?(display, change)
    }
}

private func displayReconfigurationCallback(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    let change = DisplayChange(flags)
    guard let userInfo, !change.isEmpty else { return }
    let monitor = Unmanaged<DisplayReconfigurationMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    // Delivered on the main run loop for GUI processes; hop explicitly so isolation is guaranteed.
    DispatchQueue.main.async {
        MainActor.assumeIsolated { monitor.deliver(display, change) }
    }
}
