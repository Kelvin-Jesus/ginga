import Foundation
import Tab2MacCore
import Testing
import VirtualDisplay
@testable import DisplayCapture
@testable import Tab2MacSession

@Suite("Tab2MacConfiguration")
struct Tab2MacConfigurationTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tab2mac-tests-\(UUID().uuidString)")
            .appendingPathComponent("config.json")
    }

    @Test func defaultConfigurationIsValid() throws {
        try Tab2MacConfiguration().validate()
    }

    @Test func storeReturnsDefaultsWhenNoFileExists() throws {
        let store = ConfigurationStore(fileURL: temporaryURL())
        #expect(try store.load() == Tab2MacConfiguration())
    }

    @Test func storeRoundTripsAConfiguration() throws {
        let store = ConfigurationStore(fileURL: temporaryURL())
        var configuration = Tab2MacConfiguration(display: DeviceProfile.galaxyTabS11.configuration(orientation: .portrait, refreshRate: 120))
        configuration.capture.showsCursor = false
        configuration.display.arrangement = DisplayArrangement(placement: .left, alignment: .end)
        try store.save(configuration)
        #expect(try store.load() == configuration)
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    @Test func storeRefusesToSaveAnInvalidConfiguration() {
        let store = ConfigurationStore(fileURL: temporaryURL())
        var configuration = Tab2MacConfiguration()
        configuration.display.refreshRate = 0
        #expect(throws: (any Error).self) { try store.save(configuration) }
    }

    /// `displayLingerSeconds: null` means "keep the display"; saving must not turn it back into
    /// the default by leaving the key out.
    @Test func explicitNullsSurviveASave() throws {
        let store = ConfigurationStore(fileURL: temporaryURL())
        defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
        var configuration = Tab2MacConfiguration()
        configuration.streaming.displayLingerSeconds = nil
        configuration.power.batteryRefreshRate = nil
        try store.save(configuration)
        let loaded = try store.load()
        #expect(loaded.streaming.displayLingerSeconds == nil)
        #expect(loaded.power.batteryRefreshRate == nil)
        // And an absent key still means the default.
        #expect(try JSONDecoder().decode(StreamingSettings.self, from: Data("{}".utf8)).displayLingerSeconds == 15)
    }

    /// A hand-edited file with a mistake (or one from a newer version) is the user's work: the
    /// first save keeps it aside instead of overwriting it.
    @Test func anUnreadableFileIsKeptNotOverwritten() throws {
        let store = ConfigurationStore(fileURL: temporaryURL())
        let directory = store.fileURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let broken = Data(#"{"display": {"refreshRate": 1200}, "streaming": {"wifi": true,}}"#.utf8)
        try broken.write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }

        let kept = try #require(try store.save(Tab2MacConfiguration()))
        #expect(try Data(contentsOf: kept) == broken)
        #expect(kept.lastPathComponent.hasPrefix("config.unreadable-"))
        #expect(try store.load() == Tab2MacConfiguration())
        #expect(try store.save(Tab2MacConfiguration()) == nil)  // a readable file is simply replaced
    }

    @Test func settingsOutsideTheirRangeAreRejectedByName() {
        func problem(_ change: (inout Tab2MacConfiguration) -> Void) -> String? {
            var configuration = Tab2MacConfiguration()
            change(&configuration)
            do {
                try configuration.validate()
                return nil
            } catch let error as SettingError {
                return error.key
            } catch {
                return "\(error)"
            }
        }
        #expect(problem { _ in } == nil)
        #expect(problem { $0.streaming.bitrateKbps = 0 } == "streaming.bitrateKbps")
        #expect(problem { $0.streaming.port = 0 } == "streaming.port")
        #expect(problem { $0.streaming.helloTimeoutSeconds = 0 } == "streaming.helloTimeoutSeconds")
        #expect(problem { $0.streaming.displayLingerSeconds = -1 } == "streaming.displayLingerSeconds")
        #expect(problem { $0.streaming.displayLingerSeconds = nil } == nil)
        #expect(problem { $0.power.batteryRefreshRate = 0 } == "power.batteryRefreshRate")
        #expect(problem { $0.diagnostics.sampleIntervalSeconds = 0.01 } == "diagnostics.sampleIntervalSeconds")
        #expect(problem { $0.capture.maxFrameRate = 1000 } == "capture.maxFrameRate")
    }

    @Test func knownDevicesAreRecognisedByModel() {
        #expect(DeviceProfile.matching(model: "SM-X730")?.id == "galaxy-tab-s11")
        #expect(DeviceProfile.matching(model: "SM-X616B")?.id == "galaxy-tab-s9-fe-plus")
        #expect(DeviceProfile.matching(model: "SM-S938B")?.id == "galaxy-s25-ultra")
        #expect(DeviceProfile.matching(model: "Pixel 9") == nil)
        #expect(DeviceProfile.galaxyTabS9FEPlus.configuration().refreshRate == 60)
        #expect(DeviceProfile.galaxyS25Ultra.panel.nativePixels == PixelSize(width: 3120, height: 1440))
        for profile in DeviceProfile.all { #expect((try? profile.configuration().validate()) != nil, "\(profile.id)") }
    }

    @Test func unknownDevicesGetAProfileFromWhatTheyReport() throws {
        let phone = DeviceProfile.generic(model: "Pixel 9", widthPx: 1080, heightPx: 2424, densityDpi: 422, refreshRates: [60, 90, 120])
        #expect(phone.panel.nativePixels == PixelSize(width: 2424, height: 1080))
        #expect(phone.defaultResolution == PointSize(width: 1212, height: 540))
        #expect(phone.panel.maxRefreshRate == 120)
        let size = phone.panel.physicalSize
        #expect(abs((size.widthMillimeters * size.widthMillimeters + size.heightMillimeters * size.heightMillimeters).squareRoot() / 25.4 - 6.29) < 0.1)
        try phone.configuration().validate()
    }

    @Test func newerFileVersionsAreRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Tab2MacConfiguration.self, from: Data(#"{"version": 99}"#.utf8))
        }
    }

    @Test func captureSettingsFollowTheDisplay() {
        let panel = PixelSize(width: 2560, height: 1600)
        let uncapped = CaptureSettings(maxFrameRate: nil).captureConfiguration(frameRate: 120, panel: panel)
        #expect(uncapped.frameRate == 120)
        #expect(uncapped.frameIntervalHeadroom == 2)
        #expect(uncapped.maxOutputSize == panel)
        let unbounded = CaptureSettings(limitToPanelResolution: false).captureConfiguration(frameRate: 60, panel: panel)
        #expect(unbounded.maxOutputSize == nil)
    }

    @Test func streamFollowsTheDisplayUnlessCapped() throws {
        let panel = PixelSize(width: 2560, height: 1600)
        // Default: no cap, the stream runs at the display's rate.
        let settings = CaptureSettings()
        #expect(settings.maxFrameRate == nil)
        #expect(settings.streamFrameRate(displayRefresh: 60) == 60)
        #expect(settings.streamFrameRate(displayRefresh: 120) == 120)
        #expect(settings.captureConfiguration(frameRate: 120, panel: panel).frameRate == 120)
        // A cap below the display: capture every vsync, FrameCadence picks the stream rate.
        let capped = CaptureSettings(maxFrameRate: 60)
        #expect(capped.streamFrameRate(displayRefresh: 120) == 60)
        #expect(capped.streamFrameRate(displayRefresh: 50) == 50)
        #expect(capped.captureConfiguration(frameRate: 120, panel: panel).frameRate == 120)
        #expect(capped.captureConfiguration(frameRate: 120, panel: panel).frameIntervalHeadroom == 2)
        // Or let ScreenCaptureKit drop the surplus.
        let dropping = CaptureSettings(maxFrameRate: 60, decimation: .captureService).captureConfiguration(frameRate: 120, panel: panel)
        #expect(dropping.frameRate == 60)
        #expect(dropping.frameIntervalHeadroom == CaptureSettings.decimationHeadroom)
        // JSON: absent = default (no cap); explicit values and null round-trip.
        #expect(try JSONDecoder().decode(CaptureSettings.self, from: Data("{}".utf8)).maxFrameRate == nil)
        #expect(try JSONDecoder().decode(CaptureSettings.self, from: Data(#"{"maxFrameRate": 60}"#.utf8)).maxFrameRate == 60)
        #expect(try JSONDecoder().decode(CaptureSettings.self, from: Data(#"{"maxFrameRate": null}"#.utf8)).maxFrameRate == nil)
        #expect(try JSONDecoder().decode(CaptureSettings.self, from: Data(#"{"decimation": "capture-service"}"#.utf8)).decimation == .captureService)
    }

    @Test func encoderIsPowerEfficientOnBatteryByDefault() throws {
        let policy = StreamingSettings().encoderPower
        #expect(policy == .automatic)
        #expect(policy.maximizesEfficiency(onBattery: true))
        #expect(!policy.maximizesEfficiency(onBattery: false))
        #expect(!EncoderPowerPolicy.lowestLatency.maximizesEfficiency(onBattery: true))
        #expect(EncoderPowerPolicy.lowestPower.maximizesEfficiency(onBattery: false))
        let decoded = try JSONDecoder().decode(StreamingSettings.self, from: Data(#"{"encoderPower": "lowest-latency"}"#.utf8))
        #expect(decoded.encoderPower == .lowestLatency)
    }

    @Test func onBatteryTheDisplayRunsNoFasterThanTheBatteryRate() throws {
        var configuration = Tab2MacConfiguration()
        configuration.display.refreshRate = 120
        #expect(configuration.effectiveDisplay(onBattery: false).refreshRate == 120)
        #expect(configuration.effectiveDisplay(onBattery: true).refreshRate == 60)
        configuration.power.batteryRefreshRate = nil  // "keep 120 Hz on battery"
        #expect(configuration.effectiveDisplay(onBattery: true).refreshRate == 120)
        configuration.display.refreshRate = 60
        configuration.power.batteryRefreshRate = 120  // never *raises* the rate
        #expect(configuration.effectiveDisplay(onBattery: true).refreshRate == 60)
        // JSON: absent = 60, explicit null = keep the configured rate.
        #expect(try JSONDecoder().decode(PowerSettings.self, from: Data("{}".utf8)).batteryRefreshRate == 60)
        #expect(try JSONDecoder().decode(PowerSettings.self, from: Data(#"{"batteryRefreshRate": null}"#.utf8)).batteryRefreshRate == nil)
        let roundTrip = try JSONDecoder().decode(PowerSettings.self, from: JSONEncoder().encode(PowerSettings(batteryRefreshRate: nil)))
        #expect(roundTrip.batteryRefreshRate == nil)
    }

    @Test func profilesDefaultTo60HzForPower() {
        #expect(DeviceProfile.galaxyTabS11.configuration().refreshRate == 60)
        #expect(DeviceProfile.galaxyTabS11.configuration(refreshRate: 120).refreshRate == 120)
    }

    /// Keeps the published example files honest.
    @Test func exampleConfigurationFilesDecodeAndValidate() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tab2MacSessionTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // mac
            .deletingLastPathComponent()  // repository root
        let directory = repositoryRoot.appendingPathComponent("config/examples")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count >= 4)
        for file in files {
            let configuration = try JSONDecoder().decode(Tab2MacConfiguration.self, from: Data(contentsOf: file))
            try configuration.validate()
        }
    }
}
