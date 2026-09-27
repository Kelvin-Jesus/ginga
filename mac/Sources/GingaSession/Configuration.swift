import DisplayCapture
import Foundation
import GingaCore
import VideoPipeline
import VirtualDisplay

/// Root configuration file (`~/Library/Application Support/Ginga/config.json`).
///
/// Every section decodes with defaults for missing keys, so files only need what they change and
/// older files keep working as sections are added (transport, encoder, … in later milestones).
public struct GingaConfiguration: Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var display: VirtualDisplayConfiguration
    public var capture: CaptureSettings
    public var streaming: StreamingSettings
    public var power: PowerSettings
    public var diagnostics: DiagnosticsSettings
    public var input: InputSettings

    public init(
        display: VirtualDisplayConfiguration = DeviceProfile.default.configuration(),
        capture: CaptureSettings = CaptureSettings(),
        streaming: StreamingSettings = StreamingSettings(),
        power: PowerSettings = PowerSettings(),
        diagnostics: DiagnosticsSettings = DiagnosticsSettings(),
        input: InputSettings = InputSettings()
    ) {
        self.version = Self.currentVersion
        self.display = display
        self.capture = capture
        self.streaming = streaming
        self.power = power
        self.diagnostics = diagnostics
        self.input = input
    }

    public func validate() throws {
        try display.validate()
        try capture.validate()
        try capture.captureConfiguration(frameRate: display.refreshRate, panel: display.panel.nativePixels).validate()
        try streaming.validate()
        try power.validate()
        try diagnostics.validate()
    }

    /// The display as it should run now: on battery, no faster than `power.batteryRefreshRate`.
    public func effectiveDisplay(onBattery: Bool) -> VirtualDisplayConfiguration {
        var effective = display
        if onBattery, let limit = power.batteryRefreshRate, limit < effective.refreshRate {
            effective.refreshRate = limit
        }
        return effective
    }
}

/// Battery-aware behaviour.
public struct PowerSettings: Hashable, Sendable, Codable {
    /// On battery the display runs no faster than this (nil: always the configured rate). With the
    /// display at 120 Hz that means 120 Hz on the power adapter and 60 Hz on battery, which saves
    /// about 0.8 W on the Mac for continuous motion and halves the tablet's decoding.
    public var batteryRefreshRate: Double?

    public init(batteryRefreshRate: Double? = 60) {
        self.batteryRefreshRate = batteryRefreshRate
    }

    enum CodingKeys: String, CodingKey { case batteryRefreshRate }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent = default (60); an explicit null keeps the configured rate on battery.
        batteryRefreshRate = container.contains(.batteryRefreshRate)
            ? try container.decodeIfPresent(Double.self, forKey: .batteryRefreshRate) : PowerSettings().batteryRefreshRate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(batteryRefreshRate, forKey: .batteryRefreshRate)  // null is meaningful
    }

    public func validate() throws(SettingError) {
        if let rate = batteryRefreshRate, !VirtualDisplayConfiguration.supportedRefreshRates.contains(rate) {
            throw SettingError("power.batteryRefreshRate", "\(rate) Hz is outside \(VirtualDisplayConfiguration.supportedRefreshRates)")
        }
    }
}

/// A setting Ginga can't use, named by its key path in the configuration file.
public struct SettingError: Error, Hashable, Sendable, CustomStringConvertible {
    public let key: String
    public let problem: String

    public init(_ key: String, _ problem: String) {
        self.key = key
        self.problem = problem
    }

    public var description: String { "\(key): \(problem)" }
}

extension GingaConfiguration: Codable {
    enum CodingKeys: String, CodingKey { case version, display, capture, streaming, power, diagnostics, input }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        guard version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "configuration version \(version) is newer than supported (\(Self.currentVersion))")
        }
        self.init(
            display: try container.decodeIfPresent(VirtualDisplayConfiguration.self, forKey: .display) ?? DeviceProfile.default.configuration(),
            capture: try container.decodeIfPresent(CaptureSettings.self, forKey: .capture) ?? CaptureSettings(),
            streaming: try container.decodeIfPresent(StreamingSettings.self, forKey: .streaming) ?? StreamingSettings(),
            power: try container.decodeIfPresent(PowerSettings.self, forKey: .power) ?? PowerSettings(),
            diagnostics: try container.decodeIfPresent(DiagnosticsSettings.self, forKey: .diagnostics) ?? DiagnosticsSettings(),
            input: try container.decodeIfPresent(InputSettings.self, forKey: .input) ?? InputSettings()
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(display, forKey: .display)
        try container.encode(capture, forKey: .capture)
        try container.encode(streaming, forKey: .streaming)
        try container.encode(power, forKey: .power)
        try container.encode(diagnostics, forKey: .diagnostics)
        try container.encode(input, forKey: .input)
    }
}

/// User-facing capture options; the frame rate always follows the display's refresh rate.
public struct CaptureSettings: Hashable, Sendable {
    public var pixelFormat: CapturePixelFormat
    public var showsCursor: Bool
    public var queueDepth: Int
    public var frameIntervalHeadroom: Double
    /// Downscale scaled ("more space") modes to the tablet's native pixels instead of sending more.
    public var limitToPanelResolution: Bool
    /// Optional cap on streamed frames per second below the display's refresh rate (e.g. for a
    /// slow link). nil (default) streams at the display's rate: 60 Hz by default, 120 Hz opt-in.
    public var maxFrameRate: Double?
    /// Where frames above the stream rate are dropped.
    public var decimation: FrameDecimation

    /// Minimum-interval headroom when ScreenCaptureKit decimates: 1/(rate × 1.15) accepts every
    /// second vsync of a 120 Hz display for a 60 fps stream despite timestamp jitter.
    public static let decimationHeadroom = 1.15

    public init(
        pixelFormat: CapturePixelFormat = .yuv420VideoRange,
        showsCursor: Bool = true,
        queueDepth: Int = 5,
        frameIntervalHeadroom: Double = 2,
        limitToPanelResolution: Bool = true,
        maxFrameRate: Double? = nil,
        decimation: FrameDecimation = .inProcess
    ) {
        self.pixelFormat = pixelFormat
        self.showsCursor = showsCursor
        self.queueDepth = queueDepth
        self.frameIntervalHeadroom = frameIntervalHeadroom
        self.limitToPanelResolution = limitToPanelResolution
        self.maxFrameRate = maxFrameRate
        self.decimation = decimation
    }

    /// `frameRate` is the display's refresh rate. When the stream is capped below it, every frame
    /// is captured and `FrameCadence` picks exactly the stream rate from capture timestamps
    /// (default). ScreenCaptureKit's own dropping (`.captureService`) is cheaper but judges by
    /// jittery delivery times: 120 Hz → 60 measured 50 fps with 33 ms gaps.
    public func captureConfiguration(frameRate: Double, panel: PixelSize) -> CaptureConfiguration {
        let streamRate = streamFrameRate(displayRefresh: frameRate)
        let decimatesInCapture = decimation == .captureService && streamRate < frameRate
        return CaptureConfiguration(
            frameRate: decimatesInCapture ? streamRate : frameRate,
            maxOutputSize: limitToPanelResolution ? panel : nil,
            frameIntervalHeadroom: decimatesInCapture ? Self.decimationHeadroom : frameIntervalHeadroom,
            pixelFormat: pixelFormat,
            showsCursor: showsCursor,
            queueDepth: queueDepth
        )
    }

    /// Frames per second that are encoded and streamed (≤ the display refresh rate).
    public func streamFrameRate(displayRefresh: Double) -> Double {
        maxFrameRate.map { min($0, displayRefresh) } ?? displayRefresh
    }

    public func validate() throws(SettingError) {
        if let cap = maxFrameRate, !CaptureConfiguration.supportedFrameRates.contains(cap) {
            throw SettingError("capture.maxFrameRate", "\(cap) fps is outside \(CaptureConfiguration.supportedFrameRates)")
        }
    }

    public func captureConfiguration(for display: ActiveVirtualDisplay) -> CaptureConfiguration {
        captureConfiguration(
            frameRate: display.mode?.refreshRate ?? display.configuration.refreshRate,
            panel: display.configuration.panel.nativePixels
        )
    }
}

/// Where frames above the stream rate are dropped.
public enum FrameDecimation: String, Codable, Sendable, CaseIterable {
    /// ScreenCaptureKit skips them (`minimumFrameInterval`): no conversion or wake-up for skipped
    /// frames, but an irregular cadence.
    case captureService = "capture-service"
    /// Every composed frame is captured and the stream picks on a fixed cadence (default).
    case inProcess = "in-process"
}

extension CaptureSettings: Codable {
    enum CodingKeys: String, CodingKey { case pixelFormat, showsCursor, queueDepth, frameIntervalHeadroom, limitToPanelResolution, maxFrameRate, decimation }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CaptureSettings()
        self.init(
            pixelFormat: try container.decodeIfPresent(CapturePixelFormat.self, forKey: .pixelFormat) ?? defaults.pixelFormat,
            showsCursor: try container.decodeIfPresent(Bool.self, forKey: .showsCursor) ?? defaults.showsCursor,
            queueDepth: try container.decodeIfPresent(Int.self, forKey: .queueDepth) ?? defaults.queueDepth,
            frameIntervalHeadroom: try container.decodeIfPresent(Double.self, forKey: .frameIntervalHeadroom) ?? defaults.frameIntervalHeadroom,
            limitToPanelResolution: try container.decodeIfPresent(Bool.self, forKey: .limitToPanelResolution) ?? defaults.limitToPanelResolution,
            maxFrameRate: container.contains(.maxFrameRate) ? try container.decodeIfPresent(Double.self, forKey: .maxFrameRate) : defaults.maxFrameRate,
            decimation: try container.decodeIfPresent(FrameDecimation.self, forKey: .decimation) ?? defaults.decimation
        )
    }
}

/// Streaming to receivers (M3/M4: USB via ADB reverse; AOA and Wi‑Fi later).
public struct StreamingSettings: Hashable, Sendable {
    /// Preferred codec; falls back to the other if the receiver can't decode it.
    public var codec: VideoCodec
    /// USB links are fast and loss-free, so a generous fixed rate keeps text sharp.
    public var bitrateKbps: Int
    /// Loopback TCP port the tablet reaches through `adb reverse`.
    public var port: UInt16
    /// Keep `adb reverse` in place for every authorised tablet.
    public var adbAutoReverse: Bool
    /// Close connections that don't say HELLO in time.
    public var helloTimeoutSeconds: Double
    /// Latency vs power trade-off of the hardware encoder.
    public var encoderPower: EncoderPowerPolicy
    /// A display created because a tablet connected is removed this long after the last tablet
    /// disconnects (windows return to the Mac's screens, nothing is composed for nobody). Short
    /// drops reconnect onto the same display. nil keeps it until the app quits.
    public var displayLingerSeconds: Double?
    /// M6: switch approved Android devices to USB accessory mode (no developer mode, no adb).
    public var directUSB: Bool
    /// Serial numbers of the devices the user approved for direct USB.
    public var approvedUSBDevices: [String]
    /// M7: accept paired tablets over Wi‑Fi (TLS, Bonjour `_ginga._tcp`).
    public var wifi: Bool
    /// A display created because a tablet connected takes that tablet's panel (its size,
    /// density and fastest refresh), when it's another device than the configured one.
    public var matchTabletDisplay: Bool

    public init(
        codec: VideoCodec = .hevc, bitrateKbps: Int = 40_000, port: UInt16 = 47800, adbAutoReverse: Bool = true,
        helloTimeoutSeconds: Double = 5, encoderPower: EncoderPowerPolicy = .automatic, displayLingerSeconds: Double? = 15,
        directUSB: Bool = true, approvedUSBDevices: [String] = [], wifi: Bool = false, matchTabletDisplay: Bool = true
    ) {
        self.matchTabletDisplay = matchTabletDisplay
        self.codec = codec
        self.bitrateKbps = bitrateKbps
        self.port = port
        self.adbAutoReverse = adbAutoReverse
        self.helloTimeoutSeconds = helloTimeoutSeconds
        self.encoderPower = encoderPower
        self.displayLingerSeconds = displayLingerSeconds
        self.directUSB = directUSB
        self.approvedUSBDevices = approvedUSBDevices
        self.wifi = wifi
    }
}

/// `MaximizePowerEfficiency` on the encoder: about 40% less encoder power (AVE 112 → 69 mW at
/// 2560×1600 @60) for about 6 ms more encode time (5.9 → 12.1 ms p50), `ginga bench-encode --sweep`.
public enum EncoderPowerPolicy: String, Codable, Sendable, CaseIterable {
    /// Lowest latency on AC power, power-efficient on battery (default).
    case automatic
    case lowestLatency = "lowest-latency"
    case lowestPower = "lowest-power"

    public func maximizesEfficiency(onBattery: Bool) -> Bool {
        switch self {
        case .automatic: onBattery
        case .lowestLatency: false
        case .lowestPower: true
        }
    }
}

extension StreamingSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case codec, bitrateKbps, port, adbAutoReverse, helloTimeoutSeconds, encoderPower, displayLingerSeconds, directUSB, approvedUSBDevices, wifi, matchTabletDisplay
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StreamingSettings()
        self.init(
            codec: try container.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? defaults.codec,
            bitrateKbps: try container.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? defaults.bitrateKbps,
            port: try container.decodeIfPresent(UInt16.self, forKey: .port) ?? defaults.port,
            adbAutoReverse: try container.decodeIfPresent(Bool.self, forKey: .adbAutoReverse) ?? defaults.adbAutoReverse,
            helloTimeoutSeconds: try container.decodeIfPresent(Double.self, forKey: .helloTimeoutSeconds) ?? defaults.helloTimeoutSeconds,
            encoderPower: try container.decodeIfPresent(EncoderPowerPolicy.self, forKey: .encoderPower) ?? defaults.encoderPower,
            displayLingerSeconds: container.contains(.displayLingerSeconds)
                ? try container.decodeIfPresent(Double.self, forKey: .displayLingerSeconds) : defaults.displayLingerSeconds,
            directUSB: try container.decodeIfPresent(Bool.self, forKey: .directUSB) ?? defaults.directUSB,
            approvedUSBDevices: try container.decodeIfPresent([String].self, forKey: .approvedUSBDevices) ?? defaults.approvedUSBDevices,
            wifi: try container.decodeIfPresent(Bool.self, forKey: .wifi) ?? defaults.wifi,
            matchTabletDisplay: try container.decodeIfPresent(Bool.self, forKey: .matchTabletDisplay) ?? defaults.matchTabletDisplay
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(codec, forKey: .codec)
        try container.encode(bitrateKbps, forKey: .bitrateKbps)
        try container.encode(port, forKey: .port)
        try container.encode(adbAutoReverse, forKey: .adbAutoReverse)
        try container.encode(helloTimeoutSeconds, forKey: .helloTimeoutSeconds)
        try container.encode(encoderPower, forKey: .encoderPower)
        try container.encode(displayLingerSeconds, forKey: .displayLingerSeconds)  // null (keep the display) is meaningful
        try container.encode(directUSB, forKey: .directUSB)
        try container.encode(approvedUSBDevices, forKey: .approvedUSBDevices)
        try container.encode(wifi, forKey: .wifi)
        try container.encode(matchTabletDisplay, forKey: .matchTabletDisplay)
    }
}

extension StreamingSettings {
    public static let supportedBitrates = 1_000...200_000
    public static let supportedHelloTimeouts = 0.5...600.0
    public static let supportedLinger = 0.0...86_400.0

    public func validate() throws(SettingError) {
        guard Self.supportedBitrates.contains(bitrateKbps) else {
            throw SettingError("streaming.bitrateKbps", "\(bitrateKbps) is outside \(Self.supportedBitrates)")
        }
        guard port != 0 else { throw SettingError("streaming.port", "must be a fixed port (the tablet connects to it)") }
        guard Self.supportedHelloTimeouts.contains(helloTimeoutSeconds) else {
            throw SettingError("streaming.helloTimeoutSeconds", "\(helloTimeoutSeconds) is outside \(Self.supportedHelloTimeouts)")
        }
        if let linger = displayLingerSeconds, !Self.supportedLinger.contains(linger) {
            throw SettingError("streaming.displayLingerSeconds", "\(linger) is outside \(Self.supportedLinger) (null keeps the display)")
        }
    }
}

public struct DiagnosticsSettings: Hashable, Sendable {
    /// Show the statistics overlay on the debug preview.
    public var overlayEnabled: Bool
    /// How often diagnostics (FPS, latency, CPU, GPU, memory) are sampled for the UI.
    public var sampleIntervalSeconds: Double

    public init(overlayEnabled: Bool = true, sampleIntervalSeconds: Double = 1) {
        self.overlayEnabled = overlayEnabled
        self.sampleIntervalSeconds = sampleIntervalSeconds
    }
}

extension DiagnosticsSettings {
    public static let supportedSampleIntervals = 0.25...60.0

    public func validate() throws(SettingError) {
        guard Self.supportedSampleIntervals.contains(sampleIntervalSeconds) else {
            throw SettingError("diagnostics.sampleIntervalSeconds", "\(sampleIntervalSeconds) is outside \(Self.supportedSampleIntervals)")
        }
    }
}

extension DiagnosticsSettings: Codable {
    enum CodingKeys: String, CodingKey { case overlayEnabled, sampleIntervalSeconds }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overlayEnabled: try container.decodeIfPresent(Bool.self, forKey: .overlayEnabled) ?? true,
            sampleIntervalSeconds: try container.decodeIfPresent(Double.self, forKey: .sampleIntervalSeconds) ?? 1
        )
    }
}

/// Loads and saves the configuration file atomically.
public struct ConfigurationStore: Sendable {
    public let fileURL: URL

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ginga/config.json")
    }

    public init(fileURL: URL = ConfigurationStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// The stored configuration, or the defaults when no file exists yet.
    public func load() throws -> GingaConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return GingaConfiguration() }
        let configuration = try JSONDecoder().decode(GingaConfiguration.self, from: Data(contentsOf: fileURL))
        try configuration.validate()
        return configuration
    }

    /// Writes the configuration. A file that can't be read (hand-edited with a mistake, or from a
    /// newer version) is never overwritten: it is kept next to it, and its new name returned.
    @discardableResult
    public func save(_ configuration: GingaConfiguration) throws -> URL? {
        try configuration.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let kept = try keepIfUnreadable()
        try data.write(to: fileURL, options: .atomic)
        return kept
    }

    private func keepIfUnreadable() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path), (try? load()) == nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(fileURL.deletingPathExtension().lastPathComponent).unreadable-\(formatter.string(from: Date())).json"
        let kept = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: fileURL, to: kept)
        return kept
    }
}

/// Touch, pen and keyboard from the tablet.
public struct InputSettings: Hashable, Sendable {
    /// What one finger does.
    public enum TouchMode: String, Codable, Sendable, CaseIterable {
        /// Tap clicks, drag drags, long press right-clicks (default).
        case pointer
        /// Like Sidecar: fingers only scroll (two fingers); point and click with the S Pen.
        case gestures
    }

    /// Which key of the tablet's PC-style keyboard acts as ⌘.
    public enum CommandKey: String, Codable, Sendable, CaseIterable {
        /// The ⊞/Samsung key (as macOS does for a PC keyboard).
        case meta
        /// Ctrl, so Ctrl+C copies.
        case control
    }

    public var touch: TouchMode
    public var commandKey: CommandKey

    public init(touch: TouchMode = .pointer, commandKey: CommandKey = .meta) {
        self.touch = touch
        self.commandKey = commandKey
    }
}

extension InputSettings: Codable {
    enum CodingKeys: String, CodingKey { case touch, commandKey }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            touch: try container.decodeIfPresent(TouchMode.self, forKey: .touch) ?? .pointer,
            commandKey: try container.decodeIfPresent(CommandKey.self, forKey: .commandKey) ?? .meta
        )
    }
}

