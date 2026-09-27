import CoreGraphics
import GingaCore

/// Public CoreGraphics display APIs the provider needs, behind a protocol so the provider's
/// state machine can be tested without touching WindowServer.
@MainActor
public protocol SystemDisplayServices: AnyObject {
    func onlineDisplayIDs() -> [CGDirectDisplayID]
    func mainDisplayID() -> CGDirectDisplayID
    /// Global bounds in points (top-left origin).
    func bounds(of display: CGDirectDisplayID) -> CGRect
    func currentMode(of display: CGDirectDisplayID) -> DisplayModeInfo?
    func availableModes(of display: CGDirectDisplayID) -> [DisplayModeInfo]
    func setMode(_ mode: DisplayModeInfo, of display: CGDirectDisplayID) throws
    func setOrigin(_ origin: CGPoint, of display: CGDirectDisplayID) throws
    /// The display this one mirrors, or nil when it extends the desktop.
    func mirrorSource(of display: CGDirectDisplayID) -> CGDirectDisplayID?
    /// Makes `display` mirror `source`, or extend the desktop when `source` is nil.
    func setMirrorSource(_ source: CGDirectDisplayID?, of display: CGDirectDisplayID) throws
}

public enum DisplayConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    case modeNotFound(DisplayModeInfo)
    case coreGraphics(operation: String, code: Int32)

    public var description: String {
        switch self {
        case .modeNotFound(let mode): "mode \(mode) is not offered by the display"
        case .coreGraphics(let operation, let code): "CoreGraphics \(operation) failed with CGError \(code)"
        }
    }
}

/// Production implementation using documented CoreGraphics display APIs only.
@MainActor
public final class CoreGraphicsDisplayServices: SystemDisplayServices {
    public init() {}

    public func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public func mainDisplayID() -> CGDirectDisplayID {
        CGMainDisplayID()
    }

    public func bounds(of display: CGDirectDisplayID) -> CGRect {
        CGDisplayBounds(display)
    }

    public func currentMode(of display: CGDirectDisplayID) -> DisplayModeInfo? {
        CGDisplayCopyDisplayMode(display).map(DisplayModeInfo.init)
    }

    public func availableModes(of display: CGDirectDisplayID) -> [DisplayModeInfo] {
        coreGraphicsModes(of: display).map(DisplayModeInfo.init)
    }

    public func setMode(_ mode: DisplayModeInfo, of display: CGDirectDisplayID) throws {
        guard let match = coreGraphicsModes(of: display).first(where: { DisplayModeInfo($0) == mode }) else {
            throw DisplayConfigurationError.modeNotFound(mode)
        }
        try configure("set-mode") { CGConfigureDisplayWithDisplayMode($0, display, match, nil) }
    }

    public func setOrigin(_ origin: CGPoint, of display: CGDirectDisplayID) throws {
        try configure("set-origin") { CGConfigureDisplayOrigin($0, display, Int32(origin.x), Int32(origin.y)) }
    }

    public func mirrorSource(of display: CGDirectDisplayID) -> CGDirectDisplayID? {
        let source = CGDisplayMirrorsDisplay(display)
        return source == kCGNullDirectDisplay ? nil : source
    }

    public func setMirrorSource(_ source: CGDirectDisplayID?, of display: CGDirectDisplayID) throws {
        try configure("set-mirror") { CGConfigureDisplayMirrorOfDisplay($0, display, source ?? kCGNullDirectDisplay) }
    }

    private func coreGraphicsModes(of display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
    }

    /// Runs one display-configuration transaction, scoped to the login session (never saved).
    private func configure(_ operation: String, _ body: (CGDisplayConfigRef?) -> CGError) throws {
        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success else { throw DisplayConfigurationError.coreGraphics(operation: "\(operation)/begin", code: error.rawValue) }
        error = body(config)
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayConfigurationError.coreGraphics(operation: operation, code: error.rawValue)
        }
        error = CGCompleteDisplayConfiguration(config, .forSession)
        guard error == .success else { throw DisplayConfigurationError.coreGraphics(operation: "\(operation)/complete", code: error.rawValue) }
    }
}
