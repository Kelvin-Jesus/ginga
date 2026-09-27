import AppKit
import DirectLink
import DisplayCapture
import InputInjection
import Observation
import GingaCore
import GingaSecurity
import GingaSession
import GingaStreaming
import Transport
import USBAccessory
import VirtualDisplay

/// UI state and actions. Owns nothing platform-specific beyond the session it is given.
@MainActor
@Observable
final class AppModel {
    let session: DisplaySession
    /// Where settings are saved; nil when they came from `--config` (changes last for the session).
    let store: ConfigurationStore?
    let streamServer: StreamServer

    /// The configuration being edited in the control panel.
    var draft: GingaConfiguration
    private(set) var applied: GingaConfiguration
    private(set) var active: ActiveVirtualDisplay?
    private(set) var captureState: DisplaySession.CaptureState = .idle
    private(set) var statistics = CaptureStatisticsSnapshot()
    private(set) var resources: ResourceSample?
    private(set) var backendAvailability: BackendAvailability
    private(set) var screenRecordingGranted = ScreenCapturePermission.isGranted
    private(set) var lastError: String?
    private(set) var isBusy = false
    private(set) var displayFailure: String?
    private(set) var isStreamingEnabled = false
    private(set) var streaming: StreamServer.Status
    private(set) var streamFramesPerSecond: Double = 0
    private(set) var inputPermissionGranted = CGEventInjector.hasPermission

    @ObservationIgnored weak var controlWindow: NSWindow?
    @ObservationIgnored var accessories: AccessoryCoordinator? {
        didSet {
            accessories?.onChange = { [weak self] in self?.refreshUSB() }
            refreshUSB()
        }
    }
    /// Android devices on USB that can be switched to accessory mode (M6).
    @ObservationIgnored var wifi: WiFiService? {
        didSet {
            wifi?.onChange = { [weak self] in self?.refreshWiFi() }
            refreshWiFi()
        }
    }
    private(set) var wifiRunning = false
    private(set) var wifiPort: UInt16?
    private(set) var pairedTablets: [PairedTablet] = []
    private(set) var usbCandidates: [USBDeviceInfo] = []
    private(set) var directUSBEnabled = false
    private(set) var approvedUSBDevices: [String] = []
    @ObservationIgnored private var sampler = ResourceSampler()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var previewCaptureTask: Task<Void, Never>?
    /// Windows currently showing diagnostics; with none, nothing is sampled.
    @ObservationIgnored private var observers: Set<ObjectIdentifier> = []
    @ObservationIgnored private var lastFrameCount: (count: Int, time: MediaTime)?
    @ObservationIgnored private let testPattern = LoadGenerator()
    @ObservationIgnored private var testPatternRetry: DispatchWorkItem?
    /// Keep an animated test pattern on the tablet display (diagnostics / demos).
    private(set) var wantsTestPattern = false
    private(set) var isTestPatternVisible = false

    init(session: DisplaySession, store: ConfigurationStore?, configuration: GingaConfiguration, streamServer: StreamServer) {
        self.session = session
        self.store = store
        self.streamServer = streamServer
        self.draft = configuration
        self.applied = configuration
        self.streaming = streamServer.status
        self.backendAvailability = session.provider.backendAvailability()
        session.onChange = { [weak self] in self?.refresh() }
        streamServer.onChange = { [weak self] in self?.refreshStreaming() }
        // Event-driven instead of polled: NSScreen learns about a new display after CoreGraphics
        // does, and permissions change while the user is in System Settings.
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncTestPattern() }
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        refresh()
    }

    var hasPendingChanges: Bool { draft != applied }
    var savesSettings: Bool { store != nil }

    /// Shows a problem found outside an action (e.g. an unreadable settings file at launch); nil dismisses it.
    func report(_ message: String?) {
        lastError = message
    }

    /// The pairing question on screen (a sheet on the main window), until answered or moot.
    var pairingRequest: PairingRequest?

    /// Diagnostics are sampled only while their section is open in a visible window.
    var diagnosticsExpanded = false {
        didSet { if diagnosticsExpanded != oldValue { updateObservedDiagnostics() } }
    }
    /// The main window is on screen and not covered: its orbits and pulses may move.
    private(set) var mainWindowVisible = false
    @ObservationIgnored private weak var mainWindow: NSWindow?

    func mainWindowVisibilityChanged(_ window: NSWindow, visible: Bool) {
        mainWindow = window
        mainWindowVisible = visible
        updateObservedDiagnostics()
    }

    private func updateObservedDiagnostics() {
        guard let mainWindow else { return }
        setObserving(mainWindow, visible: mainWindowVisible && diagnosticsExpanded)
    }
    var profile: DeviceProfile? { draft.display.profileID.flatMap(DeviceProfile.named) }

    // MARK: Actions

    func createDisplay() async {
        await perform {
            if self.hasPendingChanges { try await self.commitDraft() }
            try await self.session.startDisplay()
        }
    }

    func removeDisplay() async {
        await perform { await self.session.stopDisplay() }
    }

    func applyChanges() async {
        await perform { try await self.commitDraft() }
    }

    func revertChanges() {
        draft = applied
    }

    func selectProfile(_ id: String) {
        guard let profile = DeviceProfile.named(id), profile.id != draft.display.profileID else { return }
        var display = profile.configuration(orientation: draft.display.orientation)
        display.arrangement = draft.display.arrangement
        draft.display = display
    }

    /// The debug preview wants frames only while it can be seen. Changes apply in call order
    /// (occlusion can flip quickly; separate tasks could land out of order).
    func setPreviewCapture(_ enabled: Bool) {
        let previous = previewCaptureTask
        previewCaptureTask = Task { [session] in
            await previous?.value
            await session.setCaptureDemand(.preview, enabled)
        }
    }

    /// Accept a tablet over USB (adb reverse → 127.0.0.1:47800).
    func setStreaming(_ enabled: Bool) {
        if enabled {
            do {
                try streamServer.start()
                isStreamingEnabled = true
            } catch {
                lastError = "Could not start the tablet server: \(error)"
            }
        } else {
            streamServer.stop()
            isStreamingEnabled = false
        }
        refreshStreaming()
    }

    // MARK: Wi‑Fi (M7)

    var wifiEnabled: Bool { applied.streaming.wifi }

    func setWiFi(_ enabled: Bool) {
        persistStreaming { $0.wifi = enabled }
        if enabled {
            wifi?.start(macName: Host.current().localizedName ?? "Mac")
        } else {
            wifi?.stop()
        }
        refreshWiFi()
    }

    func forgetTablet(_ tablet: PairedTablet) {
        wifi?.forget(tablet)
    }

    private func refreshWiFi() {
        wifiRunning = wifi?.isRunning ?? false
        wifiPort = wifi?.port
        pairedTablets = wifi?.pairedTablets ?? []
        if let error = wifi?.lastError { lastError = "Wi‑Fi: \(error)" }
    }

    // MARK: Direct USB (M6)

    func setDirectUSB(_ enabled: Bool) {
        accessories?.setEnabled(enabled)
        persistStreaming { $0.directUSB = enabled }
        if enabled, !isStreamingEnabled { setStreaming(true) }
    }

    func approveUSBDevice(_ serial: String) {
        accessories?.approve(serial: serial)
        persistStreaming { if !$0.approvedUSBDevices.contains(serial) { $0.approvedUSBDevices.append(serial) } }
    }

    func revokeUSBDevice(_ serial: String) {
        accessories?.revoke(serial: serial)
        persistStreaming { $0.approvedUSBDevices.removeAll { $0 == serial } }
    }

    /// Input settings apply at once (the router reads them per event).
    @ObservationIgnored var onInputSettings: ((InputSettings) -> Void)?
    var inputSettings: InputSettings { applied.input }

    func setInput(_ change: (inout InputSettings) -> Void) {
        change(&draft.input)
        var updated = applied
        change(&updated.input)
        applied = updated
        save(updated)
        onInputSettings?(updated.input)
    }

    /// Saves a streaming change right away (it isn't part of the display draft's Apply).
    private func persistStreaming(_ change: (inout StreamingSettings) -> Void) {
        change(&draft.streaming)
        var updated = applied
        change(&updated.streaming)
        applied = updated
        save(updated)
        streamServer.update(settings: updated.streaming)
        refreshUSB()
    }

    /// A failure to save leaves the change in effect for this session; the user is told.
    private func save(_ configuration: GingaConfiguration) {
        guard let store else { return }
        do {
            if let kept = try store.save(configuration) {
                lastError = "The settings file couldn't be read, so it was kept as \(kept.lastPathComponent) and replaced."
            }
        } catch {
            lastError = "Could not save the settings: \(error)"
        }
    }

    private func refreshUSB() {
        usbCandidates = (accessories?.candidates.values).map { Array($0) }?.sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
        directUSBEnabled = accessories?.isEnabled ?? applied.streaming.directUSB
        approvedUSBDevices = applied.streaming.approvedUSBDevices
    }

    /// Shows or hides an animated window on the tablet display (so something is always moving).
    func setTestPattern(_ enabled: Bool) {
        wantsTestPattern = enabled
        syncTestPattern()
    }

    private func syncTestPattern(attempt: Int = 0) {
        testPatternRetry?.cancel()
        testPatternRetry = nil
        guard wantsTestPattern, let active else {
            testPattern.stop()
            isTestPatternVisible = false
            return
        }
        guard let screen = DisplayInspection.screen(for: active.displayID) else {
            // AppKit learns about a new display a moment after CoreGraphics: retry briefly
            // (bounded, so nothing keeps ticking if the display never shows up).
            isTestPatternVisible = false
            guard attempt < 40 else { return }
            let retry = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.syncTestPattern(attempt: attempt + 1) }
            }
            testPatternRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: retry)
            return
        }
        let onTabletDisplay = testPattern.screen.map { screenID($0) == active.displayID } ?? false
        if !onTabletDisplay {
            testPattern.start(on: screen, title: "Ginga test pattern")
            let placed = testPattern.screen.map { screenID($0) } ?? 0
            Log.app.info("app.test-pattern display=\(active.displayID) screen=\(NSStringFromRect(screen.frame), privacy: .public) placed_on=\(placed) attempt=\(attempt)")
        }
        isTestPatternVisible = true
    }

    func requestInputPermission() {
        CGEventInjector.requestPermission()
        inputPermissionGranted = CGEventInjector.hasPermission
    }

    func requestScreenRecording() {
        if !ScreenCapturePermission.request() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        screenRecordingGranted = ScreenCapturePermission.isGranted
        if screenRecordingGranted { session.retryCapture() }
    }

    func openDisplaysSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
    }

    /// Moves the control panel onto the virtual display (or back) — the "move a window" demo.
    func toggleControlPanelPlacement() {
        guard let window = controlWindow, let active else { return }
        let onVirtual = DisplayInspection.screen(for: active.displayID)
        let home = NSScreen.screens.first { CGDisplayIsBuiltin(screenID($0)) != 0 } ?? NSScreen.main
        let target = window.screen == onVirtual ? home : onVirtual
        guard let target else { return }
        window.setFrameOrigin(NSPoint(x: target.visibleFrame.midX - window.frame.width / 2, y: target.visibleFrame.midY - window.frame.height / 2))
    }

    var isControlPanelOnVirtualDisplay: Bool {
        guard let window = controlWindow, let screen = window.screen, let active else { return false }
        return screenID(screen) == active.displayID
    }

    // MARK: Monitoring

    /// Diagnostics are sampled only while a window showing them is on screen (control panel,
    /// debug preview): with Ginga in the menu bar, nothing ticks.
    func setObserving(_ observer: AnyObject, visible: Bool) {
        let wasObserved = !observers.isEmpty
        if visible { observers.insert(ObjectIdentifier(observer)) } else { observers.remove(ObjectIdentifier(observer)) }
        if wasObserved != !observers.isEmpty { updateMonitoring() }
    }

    private func updateMonitoring() {
        timer?.invalidate()
        timer = nil
        guard !observers.isEmpty else { return }
        sample()
        let interval = max(0.25, applied.diagnostics.sampleIntervalSeconds)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = interval / 5  // lets the system coalesce the wake-up with others
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        statistics = session.captureStatistics
        resources = sampler.sample()
        refreshStreaming()
        updateStreamRate()
    }

    /// TCC lookups are IPC: done when the app becomes active (the user returns from System
    /// Settings) and after asking, not on every diagnostics tick.
    func refreshPermissions() {
        screenRecordingGranted = ScreenCapturePermission.isGranted
        inputPermissionGranted = CGEventInjector.hasPermission
    }

    private func refreshStreaming() {
        streamServer.refresh()
        streaming = streamServer.status
        let overWiFi = streamServer.isStreamingOverWiFi
        if overWiFi != wasStreamingOverWiFi {
            wasStreamingOverWiFi = overWiFi
            if overWiFi { direct?.tabletConnected() } else { direct?.tabletDisconnected() }
        }
    }

    // MARK: No router (§6b)

    @ObservationIgnored var direct: DirectLinkSession? {
        didSet { direct?.onChange = { [weak self] state in self?.directState = state } }
    }
    @ObservationIgnored private var wasStreamingOverWiFi = false
    private(set) var directState: DirectLinkSession.State = .idle

    /// Only on the user's click: the Mac leaves its current Wi‑Fi network until this ends.
    func connectDirectly() {
        guard let direct else { return }
        Task { await direct.start() }
    }

    func endDirect() {
        guard let direct else { return }
        Task {
            await direct.end()
            if !applied.streaming.wifi { wifi?.stop() }  // the listener was only up for this
        }
    }

    var directStatus: String {
        switch directState {
        case .idle: tr("Desligado", "Off")
        case .authorizing: tr("Pedindo permissão…", "Asking for permission…")
        case .searching: tr("Procurando o tablet por Bluetooth… (toque em “Sem roteador” no tablet)", "Looking for the tablet over Bluetooth… (tap “No router” on the tablet)")
        case .joining(let ssid): tr("Entrando na rede do tablet \(ssid)…", "Joining the tablet's network \(ssid)…")
        case .waitingForTablet: tr("Na rede do tablet, esperando o tablet", "On the tablet's network, waiting for the tablet")
        case .connected: tr("Conectado direto", "Connected directly")
        case .restoring: tr("Voltando para a sua rede…", "Returning to your network…")
        case .failed(let reason): tr("Falhou: \(reason)", "Failed: \(reason)")
        }
    }

    /// Sent frame rate, measured over the regular sampling interval.
    private func updateStreamRate() {
        let now = MediaTime.now()
        if let connection = streaming.connection {
            if let last = lastFrameCount, now > last.time {
                streamFramesPerSecond = Double(connection.framesSent - last.count) / (now - last.time).inSeconds
            }
            lastFrameCount = (connection.framesSent, now)
        } else {
            lastFrameCount = nil
            streamFramesPerSecond = 0
        }
    }

    private func refresh() {
        followSessionOrientation()
        let previous = active?.displayID
        active = session.activeDisplay
        captureState = session.captureState
        if case .failed(let reason) = session.provider.state { displayFailure = reason } else { displayFailure = nil }
        if active?.displayID != previous { isTestPatternVisible = false }
        syncTestPattern()
    }

    /// The tablet rotates the display (CONFIGURE orientation) through the session: follow it, so
    /// the next Apply of an unrelated change doesn't rotate it back.
    private func followSessionOrientation() {
        let orientation = session.configuration.display.orientation
        guard applied.display.orientation != orientation else { return }
        if draft.display.orientation == applied.display.orientation { draft.display.orientation = orientation }
        applied.display.orientation = orientation
    }

    /// Applies first and saves only what took effect: a configuration the display can't run
    /// never ends up in the file.
    private func commitDraft() async throws {
        let target = draft
        try await session.apply(target)
        streamServer.update(settings: target.streaming)
        onInputSettings?(target.input)
        applied = target
        updateMonitoring()
        refresh()
        save(target)
    }

    private func perform(_ work: @escaping @MainActor () async throws -> Void) async {
        isBusy = true
        lastError = nil
        defer {
            isBusy = false
            refresh()
        }
        do {
            try await work()
        } catch {
            lastError = String(describing: error)
            Log.app.error("app.action-failed reason=\(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Presentation

    var displayStatus: String {
        if let active {
            let mode = active.mode.map { "\($0.size.width)×\($0.size.height)\($0.isHiDPI ? " @2x" : "") \(Int($0.refreshRate.rounded())) Hz" } ?? "unknown mode"
            return "Active — display \(active.displayID), \(mode)\(active.isExtendingDesktop ? "" : ", mirrored")"
        }
        if let displayFailure { return "Failed — \(displayFailure)" }
        return "Not created"
    }

    var captureStatus: String {
        switch captureState {
        case .idle: "Idle (starts with the debug preview)"
        case .starting: "Starting…"
        case .running(let id): "Capturing display \(id)"
        case .waitingForPermission: "Needs Screen Recording permission"
        case .retrying(let attempt, let reason): "Retrying (\(attempt)) — \(reason)"
        case .failed(let reason): "Failed — \(reason)"
        }
    }

    var overlayLines: [String] {
        var lines: [String] = []
        if let active, let mode = active.mode {
            lines.append("display \(active.displayID) · \(mode.size.width)×\(mode.size.height)pt\(mode.isHiDPI ? " @2x" : "") · \(Int(mode.refreshRate.rounded())) Hz")
        }
        let size = statistics.lastPixelSize.map { "\($0.width)×\($0.height)" } ?? "—"
        lines.append("capture \(size) \(applied.capture.pixelFormat.rawValue) · \(String(format: "%.1f", statistics.framesPerSecond)) fps")
        if let latency = statistics.captureLatencyMilliseconds {
            let jitter = statistics.frameIntervalMilliseconds.map { String(format: " · jitter %.2f ms", $0.standardDeviation) } ?? ""
            lines.append(String(format: "capture vs vsync p50 %.2f / p95 %.2f ms", latency.p50, latency.p95) + jitter)
        }
        lines.append("frames \(statistics.completeFrames) · idle \(statistics.idleFrames) · other \(statistics.otherFrames)")
        if let resources {
            let gpu = resources.gpuDevicePercent.map { String(format: " · GPU %.0f%%", $0) } ?? ""
            lines.append(String(format: "CPU %.1f%% · mem %.0f MB", resources.cpuPercent, resources.memoryFootprintMegabytes) + gpu)
        }
        lines.append(contentsOf: streamLines)
        return lines
    }

    var tabletStatus: String {
        guard isStreamingEnabled else { return "Off" }
        guard let port = streaming.listeningPort else { return streaming.lastError.map { "Failed — \($0)" } ?? "Starting…" }
        let ready = streaming.adbDevices.filter(\.isReady)
        let devices: String
        if !streaming.adbAvailable {
            devices = "adb not found — install android-platform-tools"
        } else if ready.isEmpty {
            devices = streaming.adbDevices.isEmpty ? "no tablet on USB (enable USB debugging)" : "tablet not authorised (accept the prompt on the tablet)"
        } else {
            devices = ready.map { ($0.model ?? $0.serial).replacingOccurrences(of: "_", with: "-") }.joined(separator: ", ")
        }
        guard let connection = streaming.connection else { return "Listening on 127.0.0.1:\(port) · \(devices) · open Ginga on the tablet" }
        return "\(connection.clientModel ?? connection.endpoint) — \(connection.phase.rawValue)"
    }

    var streamLines: [String] {
        guard let connection = streaming.connection else { return [] }
        var lines: [String] = []
        let size = connection.streamSize.map { "\($0.width)×\($0.height)" } ?? "—"
        lines.append(String(format: "stream %@ %@ · %.1f fps · %.1f Mbps · skipped %d", connection.codec?.rawValue ?? "", size, streamFramesPerSecond, connection.sentKilobitsPerSecond / 1000, connection.framesSkippedForBackpressure))
        if let encode = connection.encodeMilliseconds {
            lines.append(String(format: "encode p50 %.1f / p95 %.1f ms", encode.p50, encode.p95))
        }
        if let report = connection.lastReport {
            var line = ""
            if let e2e = report.endToEndMs { line += String(format: "end-to-end p50 %.1f / p95 %.1f ms", e2e.p50, e2e.p95) }
            if let decode = report.decodeMs { line += String(format: " · decode p50 %.1f ms", decode.p50) }
            if let rtt = report.rttUs { line += String(format: " · rtt %.2f ms", Double(rtt) / 1000) }
            if let dropped = report.framesDropped { line += " · dropped \(dropped)" }
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
