import CoreGraphics
import Tab2MacCore

public struct ProviderTiming: Sendable {
    /// How long to wait for a new display to come online.
    public var onlineTimeout: Duration
    /// How long to wait for mode/origin changes to become visible before carrying on.
    public var settleTimeout: Duration
    public var pollInterval: Duration
    /// After start/apply, mode changes we did not make are treated as WindowServer restoring a
    /// mode it saved for this display identity, and the configured mode is re-selected.
    /// Afterwards they are treated as user choices (System Settings) and only reported.
    public var modeEnforcementWindow: Duration

    public init(
        onlineTimeout: Duration = .seconds(3),
        settleTimeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(20),
        modeEnforcementWindow: Duration = .seconds(3)
    ) {
        self.onlineTimeout = onlineTimeout
        self.settleTimeout = settleTimeout
        self.pollInterval = pollInterval
        self.modeEnforcementWindow = modeEnforcementWindow
    }

    public static let `default` = ProviderTiming()
}

/// A live virtual display as the rest of the system sees it.
public struct ActiveVirtualDisplay: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var configuration: VirtualDisplayConfiguration
    public var plan: VirtualDisplayPlan
    /// The mode WindowServer is actually using (the user may change it in System Settings).
    public var mode: DisplayModeInfo?
    /// Global bounds in points.
    public var bounds: CGRect
    public var mirrorSource: CGDirectDisplayID?

    /// Backing-store size — what display capture receives.
    public var pixelSize: PixelSize { mode?.pixelSize ?? plan.expectedPixelSize }
    public var isExtendingDesktop: Bool { mirrorSource == nil }
}

public enum VirtualDisplayEvent: Equatable, Sendable {
    case activated(ActiveVirtualDisplay)
    /// Mode, orientation, arrangement or mirroring changed (by us or by the user).
    case reconfigured(ActiveVirtualDisplay)
    case deactivated(CGDirectDisplayID)
    /// The display disappeared without us asking.
    case lost(CGDirectDisplayID, reason: String)
}

public enum VirtualDisplayError: Error, Hashable, Sendable, CustomStringConvertible {
    case backendUnavailable(String)
    case invalidConfiguration(String)
    case alreadyActive
    case notActive
    case timedOut(String)
    case backend(String)
    case system(String)

    public var description: String {
        switch self {
        case .backendUnavailable(let reason): "virtual display backend unavailable: \(reason)"
        case .invalidConfiguration(let reason): "invalid configuration: \(reason)"
        case .alreadyActive: "a virtual display is already active"
        case .notActive: "no virtual display is active"
        case .timedOut(let reason): "timed out: \(reason)"
        case .backend(let reason): "backend error: \(reason)"
        case .system(let reason): "display system error: \(reason)"
        }
    }
}

/// Layer 1 orchestrator: turns configurations into a live display using a `VirtualDisplayBackend`
/// for creation and public CoreGraphics APIs for mode selection, arrangement and monitoring.
///
/// The display's lifetime is independent of capture/transport: it exists from `start` until
/// `stop` (or until the system removes it), whether or not anything is consuming its frames.
@MainActor
public final class VirtualDisplayProvider {
    public enum State: Equatable, Sendable {
        case inactive
        case starting
        case active(ActiveVirtualDisplay)
        case failed(String)
    }

    public private(set) var state: State = .inactive
    public var onEvent: (@MainActor (VirtualDisplayEvent) -> Void)?

    public var activeDisplay: ActiveVirtualDisplay? {
        if case .active(let display) = state { return display }
        return nil
    }

    public var backendIdentifier: String { backend.identifier }
    public func backendAvailability() -> BackendAvailability { backend.availability() }

    private let backend: any VirtualDisplayBackend
    private let displays: any SystemDisplayServices
    private let reconfiguration: any DisplayReconfigurationSource
    private let timing: ProviderTiming
    /// Descriptor and modes actually in effect on the live display.
    private var createdDescriptor: VirtualDisplayDescriptor?
    private var appliedModeSet: VirtualDisplayModeSet?
    /// Suppresses reconfiguration callbacks caused by our own changes.
    private var isChangingConfiguration = false
    private var enforceTargetModeUntil: MediaTime?
    /// The other displays' modes from before ours appeared. Adding a display makes macOS apply the
    /// configuration it saved for the new set of displays, and scaled HiDPI modes of other
    /// monitors can become unavailable while a HiDPI virtual display exists (measured: an HDMI
    /// monitor going from 2048×864@2x 60 Hz to 2560×1080 100 Hz). Those per-set choices belong
    /// to the user (System Settings remembers them per set), so changes are reported, not undone.
    private var otherDisplayModes: [CGDirectDisplayID: DisplayModeInfo] = [:]
    private var reportOtherModesUntil: MediaTime?

    public init(
        backend: any VirtualDisplayBackend,
        displays: any SystemDisplayServices = CoreGraphicsDisplayServices(),
        reconfiguration: any DisplayReconfigurationSource = DisplayReconfigurationMonitor(),
        timing: ProviderTiming = .default
    ) {
        self.backend = backend
        self.displays = displays
        self.reconfiguration = reconfiguration
        self.timing = timing
    }

    // MARK: Lifecycle

    @discardableResult
    public func start(_ configuration: VirtualDisplayConfiguration) async throws(VirtualDisplayError) -> ActiveVirtualDisplay {
        switch state {
        case .active, .starting: throw .alreadyActive
        case .inactive, .failed: break
        }
        do {
            try configuration.validate()
        } catch {
            throw .invalidConfiguration(error.description)
        }
        let availability = backend.availability()
        guard availability.isAvailable else {
            state = .failed(availability.summary)
            Log.virtualDisplay.error("backend.unavailable backend=\(self.backend.identifier, privacy: .public) reason=\(availability.summary, privacy: .public)")
            throw .backendUnavailable(availability.summary)
        }

        let plan = VirtualDisplayPlanner.plan(for: configuration)
        state = .starting
        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        let modesBefore = currentModes(of: displays.onlineDisplayIDs())

        let displayID: CGDirectDisplayID
        do {
            displayID = try backend.createDisplay(plan.descriptor, modes: plan.modeSet) { [weak self] in
                self?.handleTermination()
            }
        } catch {
            let message = Self.describe(error)
            state = .failed(message)
            Log.virtualDisplay.error("display.create-failed reason=\(message, privacy: .public)")
            throw .backend(message)
        }
        createdDescriptor = plan.descriptor
        appliedModeSet = plan.modeSet
        Log.virtualDisplay.info("display.created id=\(displayID) name=\(plan.descriptor.name, privacy: .public) target=\(plan.target.description, privacy: .public)")

        do {
            guard await waitUntil(timeout: timing.onlineTimeout, { self.displays.onlineDisplayIDs().contains(displayID) }) else {
                throw VirtualDisplayError.timedOut("display \(displayID) did not come online within \(timing.onlineTimeout)")
            }
            let active = try await settle(displayID: displayID, configuration: configuration, plan: plan)
            state = .active(active)
            enforceTargetModeUntil = MediaTime.now().advanced(by: timing.modeEnforcementWindow)
            otherDisplayModes = modesBefore.filter { $0.key != displayID }
            reportOtherModesUntil = MediaTime.now().advanced(by: timing.modeEnforcementWindow)
            reportOtherDisplayModeChanges()
            reconfiguration.startObserving { [weak self] id, change in
                self?.handleChange(id, change)
            }
            Log.virtualDisplay.info("display.active id=\(displayID) mode=\(active.mode?.description ?? "unknown", privacy: .public) bounds=\(String(describing: active.bounds), privacy: .public)")
            onEvent?(.activated(active))
            return active
        } catch {
            backend.destroyDisplay()
            createdDescriptor = nil
            appliedModeSet = nil
            let failure = Self.wrap(error)
            state = .failed(failure.description)
            Log.virtualDisplay.error("display.start-failed id=\(displayID) reason=\(failure.description, privacy: .public)")
            throw failure
        }
    }

    /// Applies a new configuration to the live display — live when possible (mode, orientation,
    /// refresh rate, arrangement), by recreating the display when creation-time properties change.
    @discardableResult
    public func apply(_ configuration: VirtualDisplayConfiguration) async throws(VirtualDisplayError) -> ActiveVirtualDisplay {
        guard let current = activeDisplay, let createdDescriptor else {
            return try await start(configuration)
        }
        do {
            try configuration.validate()
        } catch {
            throw .invalidConfiguration(error.description)
        }
        let plan = VirtualDisplayPlanner.plan(for: configuration)
        if plan.descriptor.requiresRecreation(comparedTo: createdDescriptor) {
            Log.virtualDisplay.info("display.recreate id=\(current.displayID)")
            await stop()
            return try await start(configuration)
        }

        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        do {
            if let appliedModeSet, !plan.modeSet.hasSameModes(as: appliedModeSet) {
                try backend.setDisplayModes(plan.modeSet)
                self.appliedModeSet = plan.modeSet
                Log.virtualDisplay.info("display.modes-replaced id=\(current.displayID) count=\(plan.modeSet.modes.count)")
                _ = await waitUntil(timeout: timing.settleTimeout) {
                    DisplayModeMatcher.bestMatch(for: plan.target, in: self.displays.availableModes(of: current.displayID)) != nil
                }
            }
            let active = try await settle(displayID: current.displayID, configuration: configuration, plan: plan)
            state = .active(active)
            enforceTargetModeUntil = MediaTime.now().advanced(by: timing.modeEnforcementWindow)
            onEvent?(.reconfigured(active))
            return active
        } catch {
            let failure = Self.wrap(error)
            Log.virtualDisplay.error("display.apply-failed id=\(current.displayID) reason=\(failure.description, privacy: .public)")
            throw failure
        }
    }

    /// Removes the display. Windows on it are moved back to the remaining displays by macOS.
    public func stop() async {
        guard let displayID = activeDisplay?.displayID ?? backend.displayID else { return }
        reconfiguration.stopObserving()
        isChangingConfiguration = true
        defer { isChangingConfiguration = false }
        backend.destroyDisplay()
        _ = await waitUntil(timeout: timing.onlineTimeout) { !self.displays.onlineDisplayIDs().contains(displayID) }
        createdDescriptor = nil
        appliedModeSet = nil
        enforceTargetModeUntil = nil
        state = .inactive
        Log.virtualDisplay.info("display.destroyed id=\(displayID)")
        onEvent?(.deactivated(displayID))
    }

    // MARK: Internals

    /// Selects the target mode and applies the arrangement, tolerating WindowServer lag.
    private func settle(displayID: CGDirectDisplayID, configuration: VirtualDisplayConfiguration, plan: VirtualDisplayPlan) async throws -> ActiveVirtualDisplay {
        var targetMode: DisplayModeInfo?
        _ = await waitUntil(timeout: timing.settleTimeout) {
            targetMode = DisplayModeMatcher.bestMatch(for: plan.target, in: self.displays.availableModes(of: displayID))
            return targetMode != nil
        }
        if let targetMode {
            if displays.currentMode(of: displayID)?.matches(plan.target) != true {
                try displays.setMode(targetMode, of: displayID)
                _ = await waitUntil(timeout: timing.settleTimeout) { self.displays.currentMode(of: displayID)?.matches(plan.target) == true }
                Log.virtualDisplay.info("display.mode-selected id=\(displayID) mode=\(targetMode.description, privacy: .public)")
            }
        } else {
            Log.virtualDisplay.warning("display.mode-missing id=\(displayID) target=\(plan.target.description, privacy: .public)")
        }

        // macOS 26 can auto-mirror a new display (e.g. when it guesses it is a TV); a mirrored
        // display is not an independent screen and drops out of ScreenCaptureKit's display list.
        if let source = displays.mirrorSource(of: displayID) {
            Log.virtualDisplay.warning("display.auto-mirrored id=\(displayID) source=\(source) action=extend")
            try displays.setMirrorSource(nil, of: displayID)
            _ = await waitUntil(timeout: timing.settleTimeout) { self.displays.mirrorSource(of: displayID) == nil }
        }

        let mainID = displays.mainDisplayID()
        let size = displays.bounds(of: displayID).size
        let otherDisplays = displays.onlineDisplayIDs()
            .filter { $0 != displayID && $0 != mainID && displays.mirrorSource(of: $0) == nil }
            .map { displays.bounds(of: $0) }
        if mainID != displayID,
           let origin = DisplayArrangementPlanner.origin(
               for: configuration.arrangement,
               size: PointSize(width: Int(size.width), height: Int(size.height)),
               relativeTo: displays.bounds(of: mainID),
               avoiding: otherDisplays
           ),
           displays.bounds(of: displayID).origin != origin {
            try displays.setOrigin(origin, of: displayID)
            // macOS may snap the origin to keep displays adjacent; accept its final placement.
            _ = await waitUntil(timeout: timing.settleTimeout) { self.displays.bounds(of: displayID).origin == origin }
            Log.virtualDisplay.info("display.arranged id=\(displayID) placement=\(configuration.arrangement.placement.rawValue, privacy: .public) origin=\(String(describing: self.displays.bounds(of: displayID).origin), privacy: .public)")
        }
        return snapshot(displayID: displayID, configuration: configuration, plan: plan)
    }

    private func snapshot(displayID: CGDirectDisplayID, configuration: VirtualDisplayConfiguration, plan: VirtualDisplayPlan) -> ActiveVirtualDisplay {
        ActiveVirtualDisplay(
            displayID: displayID,
            configuration: configuration,
            plan: plan,
            mode: displays.currentMode(of: displayID),
            bounds: displays.bounds(of: displayID),
            mirrorSource: displays.mirrorSource(of: displayID)
        )
    }

    private func handleChange(_ displayID: CGDirectDisplayID, _ change: DisplayChange) {
        guard !isChangingConfiguration, let current = activeDisplay else { return }
        guard displayID == current.displayID else {
            if change.contains(.modeChanged), let deadline = reportOtherModesUntil, MediaTime.now() < deadline {
                reportOtherDisplayModeChanges()
            }
            return
        }
        Log.virtualDisplay.debug("display.changed id=\(displayID) change=\(change.description, privacy: .public)")
        if change.contains(.removed) {
            displayLost(displayID, reason: "removed by the system")
            return
        }
        if let deadline = enforceTargetModeUntil, MediaTime.now() < deadline,
           displays.currentMode(of: displayID)?.matches(current.plan.target) == false,
           let target = DisplayModeMatcher.bestMatch(for: current.plan.target, in: displays.availableModes(of: displayID)) {
            // WindowServer restored a saved mode for this identity; put ours back. The follow-up
            // reconfiguration callback reports the final state.
            do {
                try displays.setMode(target, of: displayID)
                Log.virtualDisplay.info("display.mode-reasserted id=\(displayID) mode=\(target.description, privacy: .public)")
                return
            } catch {
                Log.virtualDisplay.error("display.mode-reassert-failed id=\(displayID) reason=\(String(describing: error), privacy: .public)")
            }
        }
        let updated = snapshot(displayID: displayID, configuration: current.configuration, plan: current.plan)
        guard updated != current else { return }
        state = .active(updated)
        Log.virtualDisplay.info("display.reconfigured id=\(displayID) mode=\(updated.mode?.description ?? "unknown", privacy: .public) mirrored=\(!updated.isExtendingDesktop)")
        onEvent?(.reconfigured(updated))
    }

    private func handleTermination() {
        guard let displayID = activeDisplay?.displayID else { return }
        displayLost(displayID, reason: "terminated by the system")
    }

    private func displayLost(_ displayID: CGDirectDisplayID, reason: String) {
        reconfiguration.stopObserving()
        enforceTargetModeUntil = nil
        reportOtherModesUntil = nil
        otherDisplayModes = [:]
        backend.destroyDisplay()
        createdDescriptor = nil
        appliedModeSet = nil
        state = .inactive
        Log.virtualDisplay.error("display.lost id=\(displayID) reason=\(reason, privacy: .public)")
        onEvent?(.lost(displayID, reason: reason))
    }

    private func currentModes(of ids: [CGDirectDisplayID]) -> [CGDirectDisplayID: DisplayModeInfo] {
        var modes: [CGDirectDisplayID: DisplayModeInfo] = [:]
        for id in ids {
            if let mode = displays.currentMode(of: id) { modes[id] = mode }
        }
        return modes
    }

    /// Logs other displays whose mode macOS changed when ours appeared (once per display).
    private func reportOtherDisplayModeChanges() {
        for (id, before) in otherDisplayModes.sorted(by: { $0.key < $1.key }) {
            guard let now = displays.currentMode(of: id), !now.isSameMode(as: before) else { continue }
            otherDisplayModes[id] = nil
            Log.virtualDisplay.notice("display.other-mode-changed id=\(id) from=\(before.description, privacy: .public) to=\(now.description, privacy: .public) hint=\("macOS applies the configuration saved for this set of displays; choose the mode in System Settings while the tablet display exists and macOS remembers it", privacy: .public)")
        }
    }

    private func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = MediaTime.now().advanced(by: timeout)
        while !condition() {
            guard MediaTime.now() < deadline else { return false }
            try? await Task.sleep(for: timing.pollInterval)
        }
        return true
    }

    private static func describe(_ error: any Error) -> String {
        String(describing: error)
    }

    private static func wrap(_ error: any Error) -> VirtualDisplayError {
        switch error {
        case let error as VirtualDisplayError: error
        case let error as VirtualDisplayBackendError: .backend(error.description)
        default: .system(describe(error))
        }
    }
}
