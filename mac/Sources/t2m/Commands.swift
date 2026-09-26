import AppKit
import CGVirtualDisplayBackend
import CGVirtualDisplayShim
import CoreGraphics
import DisplayCapture
import EnergyMeter
import Foundation
import Tab2MacCore
import Tab2MacProtocol
import Tab2MacSession
import Tab2MacRuntime
import Tab2MacSecurity
import Tab2MacStreaming
import Transport
import USBAccessory
import VideoPipeline
import VirtualDisplay

let usage = """
t2m — Tab2Mac developer tool (milestone 1: virtual display + capture)

USAGE
  t2m probe [--json]
      Verify the private CGVirtualDisplay API on this macOS build and dump its runtime interface.
  t2m displays [--json]
      List online displays and their modes.
  t2m create [display options] [--seconds N]
      Create the virtual display and keep it until Ctrl-C (or for N seconds).
  t2m verify [display options] [--report PATH] [--snapshot PATH] [--no-capture] [--no-live-changes]
      Run the milestone-1 acceptance checks (exit code 0 = passed).
  t2m bench-capture [display options] [--seconds N] [--report PATH]
      Capture benchmark. Needs Screen Recording permission for the app running t2m.
  t2m protocol-vectors --out DIR
      Write the protocol golden test vectors (protocol/test-vectors) shared with the Android suite.
  t2m bench-encode [--size WxH] [--fps N] [--frames N] [--codec hevc|h264] [--bitrate KBPS] [--report PATH]
                   [--expected-rate-factor X] [--realtime] [--power-efficient] [--sweep]
      Hardware encoder benchmark on an animated synthetic source (no permissions needed), with
      encoder (AVE) energy. --sweep compares the latency/power hints.
  t2m receive [--port P] [--token HEX] [--seconds N] [--warmup N] [--snapshot PATH] [--report PATH]
      Act as the tablet on this Mac: connect to a running server (app with --serve, or t2m serve),
      decode with VideoToolbox and report fps and display→decoded latency on one clock.
  t2m bench-power [--seconds N] [--warmup N] [--repeat N] [--only a,b] [--decode] [--port P] [--app PATH] [--report PATH]
      Energy per streaming configuration: launches the app per scenario (display Hz, stream fps,
      where frames are dropped, pixel format), receives here and reads SoC energy (IOReport, no
      root) and per-process CPU/energy/wake-ups against an idle baseline. Takes ~1 min/scenario.
  t2m energy [--seconds N] [--processes a,b,c]
      SoC energy per block (IOReport) and CPU/energy/wake-ups of named processes over N seconds
      (default: Tab2Mac, WindowServer, replayd, adb) — e.g. while streaming to the real tablet.
  t2m usb [--switch SERIAL]
      List Android devices on USB with their Android Open Accessory version (read-only), or switch
      one to accessory mode (M6 direct USB; the tablet then asks to open Tab2Mac).
  t2m run [--config PATH] [--no-adb] [--direct]
      Tab2Mac without its app: the virtual display, direct USB, adb, Wi‑Fi and input, headless
      (no menu bar, no SwiftUI), for the smallest memory and energy footprint. Settings come from
      the app's config.json (read only). --direct joins the tablet's own network (no router; the
      Mac leaves its Wi‑Fi network until it ends). Permissions are those of the terminal that runs it.
  t2m serve --synthetic [--size WxH] [--fps N] [--codec hevc|h264] [--bitrate KBPS] [--port P] [--no-adb]
      Stream an animated test pattern to the tablet over USB (adb reverse tcp:47800). No virtual
      display or Screen Recording permission needed. Without --synthetic, streams the virtual
      display (needs Screen Recording for the terminal; prefer the app for that).

DISPLAY OPTIONS
  --config PATH        configuration file (see config/examples)
  --profile ID         \(DeviceProfile.all.map(\.id).joined(separator: " | "))
  --resolution WxH     "looks like" size in landscape points, e.g. 1280x800, 1440x900
  --refresh HZ         e.g. 60 or 120
  --portrait           portrait orientation
  --standard           no HiDPI (one pixel per point)
  --position P[:A]     automatic|left|right|above|below, alignment start|center|end

Capture needs Screen Recording permission. Commands started from a terminal are attributed to
the terminal app; use the Tab2Mac app (Tab2Mac.app --self-test) to run capture under its own grant.
"""

@MainActor
enum Commands {
    static func run(_ arguments: Arguments) async throws -> Int32 {
        if arguments.flags.contains("help") || arguments.command == nil || arguments.command == "help" {
            print(usage)
            return arguments.command == nil && !arguments.flags.contains("help") ? 64 : 0
        }
        switch arguments.command {
        case "probe": return probe(json: arguments.flags.contains("json"))
        case "displays": return displays(json: arguments.flags.contains("json"))
        case "create": return try await create(arguments)
        case "verify": return try await verify(arguments)
        case "bench-capture": return try await benchCapture(arguments)
        case "protocol-vectors": return try protocolVectors(arguments)
        case "serve": return try await serve(arguments)
        case "run": return try await runHeadless(arguments)
        case "bench-encode": return try await benchEncode(arguments)
        case "receive": return try await receive(arguments)
        case "bench-power": return try await benchPower(arguments)
        case "energy": return try await energy(arguments)
        case "usb": return try usb(arguments)
        default: throw CLIError.usage("unknown command '\(arguments.command ?? "")'\n\n\(usage)")
        }
    }

    // MARK: probe

    struct ProbeReport: Codable {
        var host: HostInfo
        var privateAPIUsable: Bool
        var problems: [String]
        var missingOptional: [String]
        var checks: [String]
        var screenRecordingGranted: Bool
        var postEventGranted: Bool
        var onlineDisplays: [UInt32]
        var runtimeInterface: [String]
    }

    static func probe(json: Bool) -> Int32 {
        let report = T2MPrivateAPIChecker.checkRuntime()
        let probe = ProbeReport(
            host: .current(),
            privateAPIUsable: report.isUsable,
            problems: report.problems,
            missingOptional: report.missingOptional,
            checks: report.checks,
            screenRecordingGranted: ScreenCapturePermission.isGranted,
            postEventGranted: CGPreflightPostEventAccess(),
            onlineDisplays: CoreGraphicsDisplayServices().onlineDisplayIDs(),
            runtimeInterface: T2MPrivateAPIChecker.runtimeInterfaceDump()
        )
        if json {
            printJSON(probe)
        } else {
            print("Tab2Mac probe — \(probe.host.model) (\(probe.host.chip)), macOS \(probe.host.macOSVersion)")
            print("Private CGVirtualDisplay API: \(probe.privateAPIUsable ? "USABLE" : "NOT USABLE")")
            probe.checks.forEach { print("  \($0)") }
            probe.problems.forEach { print("  problem: \($0)") }
            probe.missingOptional.forEach { print("  optional missing: \($0)") }
            print("Screen Recording permission (this process tree): \(probe.screenRecordingGranted ? "granted" : "not granted")")
            print("Post Event permission (this process tree): \(probe.postEventGranted ? "granted" : "not granted")")
            print("Online displays: \(probe.onlineDisplays)")
            print("Runtime interface:")
            probe.runtimeInterface.forEach { print("  \($0)") }
        }
        return probe.privateAPIUsable ? 0 : 1
    }

    // MARK: displays

    struct DisplayListing: Codable {
        var id: UInt32
        var name: String
        var isMain: Bool
        var isBuiltIn: Bool
        var bounds: String
        var mode: DisplayModeInfo?
        var mirrors: UInt32?
        var modeCount: Int
    }

    static func displays(json: Bool) -> Int32 {
        let services = CoreGraphicsDisplayServices()
        let listings = services.onlineDisplayIDs().map { id in
            let bounds = services.bounds(of: id)
            return DisplayListing(
                id: id,
                name: DisplayInspection.screen(for: id)?.localizedName ?? "(no NSScreen)",
                isMain: CGDisplayIsMain(id) != 0,
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                bounds: "(\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))×\(Int(bounds.height)))",
                mode: services.currentMode(of: id),
                mirrors: services.mirrorSource(of: id),
                modeCount: services.availableModes(of: id).count
            )
        }
        if json {
            printJSON(listings)
        } else {
            for listing in listings {
                let flags = [listing.isMain ? "main" : nil, listing.isBuiltIn ? "built-in" : nil, listing.mirrors.map { "mirrors \($0)" }].compactMap { $0 }
                print("\(listing.id)  \(listing.name)  \(listing.bounds)  \(listing.mode?.description ?? "no mode")  modes=\(listing.modeCount)  \(flags.joined(separator: ", "))")
            }
        }
        return 0
    }

    // MARK: create

    static func create(_ arguments: Arguments) async throws -> Int32 {
        let configuration = try arguments.configuration()
        let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend())
        let active: ActiveVirtualDisplay
        do {
            active = try await provider.start(configuration.display)
        } catch {
            throw CLIError.failed("could not create the virtual display: \(error.description)")
        }
        print("Created \"\(configuration.display.name)\" as display \(active.displayID): \(active.mode?.description ?? "unknown mode"), bounds \(active.bounds)")
        print("Open System Settings › Displays to arrange it; drag windows onto it.")

        let removeAndExit: @MainActor () async -> Void = {
            await provider.stop()
            print("Removed display \(active.displayID).")
            exit(0)
        }
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler { Task { @MainActor in await removeAndExit() } }
        interrupt.resume()
        Signals.keepAlive = interrupt

        if let seconds = try arguments.double("seconds") {
            print("Holding for \(seconds)s…")
            try? await Task.sleep(for: .milliseconds(Int64(seconds * 1000)))
            await removeAndExit()
        } else {
            print("Press Ctrl-C to remove it.")
            // Keep the display alive until interrupted.
            while true { try? await Task.sleep(for: .seconds(3600)) }
        }
        return 0
    }

    // MARK: verify

    static func verify(_ arguments: Arguments) async throws -> Int32 {
        let configuration = try arguments.configuration()
        let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend())
        let includeCapture = !arguments.flags.contains("no-capture")
        let verifier = M1Verifier(provider: provider, capture: includeCapture ? ScreenCaptureKitSource() : nil)
        let report = await verifier.run(M1Verifier.Options(
            configuration: configuration.display,
            captureSettings: configuration.capture,
            includeCapture: includeCapture,
            exerciseLiveChanges: !arguments.flags.contains("no-live-changes"),
            snapshotURL: arguments.options["snapshot"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        ))
        print(report.summary)
        if let path = arguments.options["report"] {
            try writeJSON(report, to: path)
            print("report: \(path)")
        }
        return report.passed ? 0 : 1
    }

    // MARK: bench-capture

    static func benchCapture(_ arguments: Arguments) async throws -> Int32 {
        let configuration = try arguments.configuration()
        let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend())
        let benchmark = CaptureBenchmark(provider: provider, capture: ScreenCaptureKitSource())
        do {
            let report = try await benchmark.run(configuration: configuration, captureSeconds: try arguments.double("seconds") ?? 10)
            print(report.summary)
            if let path = arguments.options["report"] {
                try writeJSON(report, to: path)
                print("report: \(path)")
            }
            return 0
        } catch {
            throw CLIError.failed(String(describing: error))
        }
    }

    // MARK: protocol-vectors

    static func protocolVectors(_ arguments: Arguments) throws -> Int32 {
        guard let out = arguments.options["out"] else { throw CLIError.usage("protocol-vectors needs --out DIR") }
        let directory = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let vectors = try ProtocolTestVectors.all()
        for vector in vectors {
            try vector.fileData().write(to: directory.appendingPathComponent("\(vector.name).json"), options: .atomic)
        }
        print("wrote \(vectors.count) vectors to \(directory.path)")
        return 0
    }

    // MARK: bench-encode

    struct EncodeBenchmarkReport: Codable {
        var benchmark = "encode"
        var date: Date
        var host: HostInfo
        var codec: String
        var size: PixelSize
        var frameRate: Double
        var bitrateKbps: Int
        var frames: Int
        var encodeMilliseconds: StatisticSummary?
        var keyframeBytes: Int
        var deltaBytes: StatisticSummary?
        var achievedMegabitsPerSecond: Double
        var cpu: ResourceSummary
        var failures: Int
        var configuration: EncoderConfiguration?
        /// SoC power while encoding (IOReport; nil where unavailable).
        var energy: EnergyBreakdown?
    }

    static func benchEncode(_ arguments: Arguments) async throws -> Int32 {
        var size = PixelSize(width: 2560, height: 1600)
        if let value = arguments.options["size"] {
            let parts = value.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { throw CLIError.usage("--size expects WxH") }
            size = PixelSize(width: parts[0], height: parts[1])
        }
        let base = EncoderConfiguration(
            codec: VideoCodec(rawValue: arguments.options["codec"] ?? "hevc") ?? .hevc,
            size: size,
            frameRate: try arguments.double("fps") ?? 60,
            bitrateKbps: Int(try arguments.double("bitrate") ?? 40_000),
            realTime: arguments.flags.contains("realtime"),
            expectedFrameRateFactor: try arguments.double("expected-rate-factor") ?? 2,
            maximizePowerEfficiency: arguments.flags.contains("power-efficient")
        )
        let frames = Int(try arguments.double("frames") ?? 600)
        let meter = try? SoCEnergyMeter()

        // --sweep compares the encoder's latency/power hints on the same content.
        var variants: [(String, EncoderConfiguration)] = [("as configured", base)]
        if arguments.flags.contains("sweep") {
            func variant(_ factor: Double, realTime: Bool = false, efficient: Bool = false) -> EncoderConfiguration {
                var configuration = base
                configuration.expectedFrameRateFactor = factor
                configuration.realTime = realTime
                configuration.maximizePowerEfficiency = efficient
                return configuration
            }
            variants = [
                ("expected 2× (default)", variant(2)),
                ("expected 1×", variant(1)),
                ("expected 2× + power-efficient", variant(2, efficient: true)),
                ("expected 1× + power-efficient", variant(1, efficient: true)),
                ("expected 1× + RealTime", variant(1, realTime: true)),
                ("expected 1× + RealTime + power-efficient", variant(1, realTime: true, efficient: true)),
            ]
        }
        var reports: [EncodeBenchmarkReport] = []
        for (name, configuration) in variants {
            let report = try await runEncodeBenchmark(configuration, frames: frames, meter: meter)
            reports.append(report)
            var line = "\(name): "
            if let summary = report.encodeMilliseconds {
                line += String(format: "encode p50 %.2f · p95 %.2f · max %.2f ms", summary.p50, summary.p95, summary.max)
            }
            line += String(format: " · %.1f Mbit/s · failures %d", report.achievedMegabitsPerSecond, report.failures)
            if let energy = report.energy {
                line += String(format: " · AVE %.0f mW · CPU %.0f · GPU %.0f · memory %.0f mW", energy.encoder, energy.cpu, energy.gpu, energy.memory)
            }
            print(line)
        }
        if let report = reports.first, variants.count == 1 {
            print(String(format: "%@ %dx%d @%.0f fps, %d kbps · frames %d · keyframe %d KB · delta p50 %.0f KB · CPU mean %.1f%%",
                         report.codec, size.width, size.height, report.frameRate, report.bitrateKbps, report.frames,
                         report.keyframeBytes / 1024, (report.deltaBytes?.p50 ?? 0) / 1024, report.cpu.cpuPercent?.mean ?? 0))
        }
        if let path = arguments.options["report"] {
            if reports.count == 1 { try writeJSON(reports[0], to: path) } else { try writeJSON(reports, to: path) }
            print("report: \(path)")
        }
        return reports.allSatisfy { $0.failures == 0 } ? 0 : 1
    }

    static func runEncodeBenchmark(_ configuration: EncoderConfiguration, frames: Int, meter: SoCEnergyMeter?) async throws -> EncodeBenchmarkReport {
        let results = LockedValue<[EncodedFrame]>([])
        let failures = LockedValue(0)
        let encoder: VideoToolboxEncoder
        do {
            encoder = try VideoToolboxEncoder(configuration: configuration) { event in
                switch event {
                case .frame(let frame): results.update { $0.append(frame) }
                case .failed, .dropped: failures.update { $0 += 1 }
                }
            }
        } catch {
            throw CLIError.failed(error.description)
        }
        let fps = configuration.frameRate
        let generator = SyntheticFrameGenerator(size: configuration.size)
        // Pre-render a ring of frames so generation cost doesn't pollute the measurement.
        let ring = (0..<12).compactMap { _ in generator.nextFrame() }
        var sampler = ResourceSampler()
        var samples: [ResourceSample] = []
        let energyStart = meter?.read()
        let start = MediaTime.now()
        for index in 0..<frames {
            let due = start.advanced(by: .nanoseconds(Int64(Double(index) / fps * 1e9)))
            if due > MediaTime.now() { try? await Task.sleep(for: due - MediaTime.now()) }
            encoder.encode(EncoderInput(pixelBuffer: ring[index % ring.count], captureTime: .now(), forceKeyframe: index == 0))
            if index % Int(max(fps / 4, 1)) == 0 { samples.append(sampler.sample()) }
        }
        encoder.flush()
        let elapsed = (MediaTime.now() - start).inSeconds
        let energyEnd = meter?.read()
        encoder.invalidate()

        let encoded = results.value
        var latency = SampleWindow(capacity: max(encoded.count, 1))
        var deltas = SampleWindow(capacity: max(encoded.count, 1))
        encoded.dropFirst().forEach {
            latency.add($0.encodeDuration.inMilliseconds)
            if !$0.isKeyframe { deltas.add(Double($0.data.count)) }
        }
        var energy: EnergyBreakdown?
        if let meter, let energyStart, let energyEnd {
            energy = EnergyBreakdown(channels: meter.channels(from: energyStart, to: energyEnd), seconds: (energyEnd.time - energyStart.time).inSeconds)
        }
        return EncodeBenchmarkReport(
            date: Date(), host: .current(), codec: configuration.codec.rawValue, size: configuration.size, frameRate: fps,
            bitrateKbps: configuration.bitrateKbps, frames: encoded.count, encodeMilliseconds: latency.summary,
            keyframeBytes: encoded.first(where: \.isKeyframe)?.data.count ?? 0, deltaBytes: deltas.summary,
            achievedMegabitsPerSecond: Double(encoded.reduce(0) { $0 + $1.data.count }) * 8 / elapsed / 1_000_000,
            cpu: ResourceSummary(samples), failures: failures.value, configuration: configuration, energy: energy
        )
    }

    // MARK: receive

    static func receive(_ arguments: Arguments) async throws -> Int32 {
        let port = UInt16(try arguments.double("port") ?? Double(TCPServer.defaultPort))
        let seconds = try arguments.double("seconds") ?? 10
        let receiver = LoopbackReceiver(port: port, token: arguments.options["token"])
        receiver.start()
        // --warmup: measure the steady state only (encoder creation and the first IDR excluded).
        if let warmup = try arguments.double("warmup"), warmup > 0 {
            try await Task.sleep(for: .milliseconds(Int64(warmup * 1000)))
            receiver.resetStatistics()
        }
        let deadline = MediaTime.now().advanced(by: .milliseconds(Int64(seconds * 1000)))
        while MediaTime.now() < deadline, !receiver.isClosed {
            try? await Task.sleep(for: .milliseconds(250))
        }
        if let path = arguments.options["snapshot"], let picture = receiver.lastPicture {
            try FrameSnapshot.writePNG(picture, to: URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            print("snapshot: \(path)")
        }
        let report = receiver.stop()
        func fmt(_ summary: StatisticSummary?) -> String {
            summary.map { String(format: "p50 %.1f ms · p95 %.1f ms · max %.1f ms", $0.p50, $0.p95, $0.max) } ?? "n/a"
        }
        print("stream: \(report.codec ?? "?") \(report.streamSize?.description ?? "?") · decoded \(report.framesDecoded)/\(report.framesReceived) frames (\(report.keyframes) key, \(report.decodeErrors) errors) in \(String(format: "%.1f", report.seconds)) s = \(String(format: "%.1f", report.framesPerSecond)) fps · \(String(format: "%.1f", report.megabitsPerSecond)) Mbit/s")
        print("display time → decoded here: \(fmt(report.displayToDecodedMilliseconds))")
        print("frame interval: \(fmt(report.frameIntervalMilliseconds)) · irregular (>1.5× median): \(report.irregularIntervals)")
        print("encode (Mac): \(fmt(report.encodeMilliseconds)) · decode (here): \(fmt(report.decodeMilliseconds)) · rtt \(report.roundTripMicros.map { "\($0) µs" } ?? "n/a")")
        if let reason = report.closeReason { print("connection closed: \(reason)") }
        if let path = arguments.options["report"] {
            try writeJSON(report, to: path)
            print("report: \(path)")
        }
        return report.framesDecoded > 0 ? 0 : 1
    }

    // MARK: bench-power

    static func benchPower(_ arguments: Arguments) async throws -> Int32 {
        let defaultApp = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            .deletingLastPathComponent().appendingPathComponent("Tab2Mac.app")
        let app = arguments.options["app"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? defaultApp
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw CLIError.usage("no app at \(app.path); run scripts/build-app.sh or pass --app")
        }
        let warmup = try arguments.double("warmup") ?? 5
        let window = try arguments.double("seconds") ?? 20
        let repeats = Int(try arguments.double("repeat") ?? 2)
        var scenarios = PowerBenchmark.scenarios(basePort: UInt16(try arguments.double("port") ?? 47830))
        if let only = arguments.options["only"] {
            let wanted = only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            scenarios = scenarios.filter { scenario in
                scenario.name == PowerBenchmark.baselineName || wanted.contains { scenario.name.lowercased().contains($0) }
            }
        }
        print("bench-power: \(scenarios.count) scenarios × \(repeats) · warm-up \(warmup) s · window \(window) s · \(app.path)")
        let measurements = await PowerBenchmark.run(
            scenarios: scenarios, app: app, warmup: .milliseconds(Int64(warmup * 1000)), window: .milliseconds(Int64(window * 1000)),
            repeats: repeats, decode: arguments.flags.contains("decode")
        ) { print($0) }
        let summaries = PowerBenchmark.summarize(measurements)
        print("")
        print(PowerBenchmark.markdownTable(summaries))
        if let path = arguments.options["report"] {
            struct Report: Encodable {
                var measurements: [PowerBenchmark.Measurement]
                var summaries: [PowerBenchmark.Summary]
            }
            try writeJSON(Report(measurements: measurements, summaries: summaries), to: path)
            print("report: \(path)")
        }
        return measurements.isEmpty ? 1 : 0
    }

    // MARK: usb

    static func usb(_ arguments: Arguments) throws -> Int32 {
        let devices = USBDeviceWatcher.currentDevices().filter { $0.isAndroidCandidate || $0.isAccessoryMode }
        if let serial = arguments.options["switch"] {
            guard let device = devices.first(where: { $0.serialNumber == serial && $0.isAndroidCandidate }) else {
                throw CLIError.failed("no Android device with serial \(serial) in normal mode")
            }
            let version = try AccessorySwitch.switchToAccessoryMode(entryID: device.entryID)
            print("switched \(serial) (AOA \(version)); it re-enumerates as 18D1:2D00/2D01 and asks to open Tab2Mac")
            return 0
        }
        if devices.isEmpty { print("no Android devices on USB") }
        for device in devices {
            let mode = device.isAccessoryMode ? "accessory mode" : "normal mode"
            var line = String(format: "%04x:%04x  %@  %@  (%@)", device.vendorID, device.productID,
                              device.name ?? "?", device.serialNumber ?? "no serial", mode)
            if device.isAndroidCandidate {
                line += (try? AccessorySwitch.protocolVersion(entryID: device.entryID)).map { "  AOA \($0)" } ?? "  AOA unknown"
            }
            print(line)
        }
        return 0
    }

    // MARK: energy

    static func energy(_ arguments: Arguments) async throws -> Int32 {
        let seconds = try arguments.double("seconds") ?? 20
        let names = (arguments.options["processes"] ?? "Tab2Mac,WindowServer,replayd,adb")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let meter: SoCEnergyMeter?
        do { meter = try SoCEnergyMeter() } catch { print("SoC energy unavailable: \(error)"); meter = nil }
        let pids = names.flatMap { name in ProcessUsage.pids(named: name).map { (name, $0) } }
        let startEnergy = meter?.read()
        let startUsage = pids.map { ($0.0, $0.1, ProcessUsage.read(pid: $0.1)) }
        let started = MediaTime.now()
        try await Task.sleep(for: .milliseconds(Int64(seconds * 1000)))
        let elapsed = (MediaTime.now() - started).inSeconds
        if let meter, let startEnergy, let endEnergy = meter.read() {
            let soc = EnergyBreakdown(channels: meter.channels(from: startEnergy, to: endEnergy), seconds: (endEnergy.time - startEnergy.time).inSeconds)
            print(String(format: "SoC %.0f mW · CPU %.0f · GPU %.0f · encoder (AVE) %.0f · decoder %.0f · memory %.0f · scaler %.0f · display %.0f · other %.0f",
                         soc.total, soc.cpu, soc.gpu, soc.encoder, soc.decoder, soc.memory, soc.scaler, soc.display, soc.other))
        }
        for (name, pid, start) in startUsage {
            guard let start, let end = ProcessUsage.read(pid: pid) else { continue }
            let rates = ProcessRates(from: start, to: end, seconds: elapsed)
            var line = String(format: "%@ (%d): %.1f%% CPU", name, pid, rates.cpuPercent)
            if let milliwatts = rates.milliwatts { line += String(format: " · %.0f mW", milliwatts) }
            if let wakeups = rates.wakeupsPerSecond { line += String(format: " · %.0f wake-ups/s", wakeups) }
            print(line)
        }
        return 0
    }

    // MARK: serve

    static func serve(_ arguments: Arguments) async throws -> Int32 {
        var configuration = try arguments.configuration()
        if let codec = arguments.options["codec"] {
            guard let value = VideoCodec(rawValue: codec) else { throw CLIError.usage("--codec expects hevc or h264") }
            configuration.streaming.codec = value
        }
        if let bitrate = try arguments.double("bitrate") { configuration.streaming.bitrateKbps = Int(bitrate) }
        if let port = try arguments.double("port") { configuration.streaming.port = UInt16(port) }
        if arguments.flags.contains("no-adb") { configuration.streaming.adbAutoReverse = false }

        let host: any StreamHost
        if arguments.flags.contains("synthetic") {
            var size = PixelSize(width: 2560, height: 1600)
            if let value = arguments.options["size"] {
                let parts = value.lowercased().split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { throw CLIError.usage("--size expects WxH") }
                size = PixelSize(width: parts[0], height: parts[1])
            }
            host = SyntheticStreamHost(size: size, frameRate: try arguments.double("fps") ?? 60)
        } else {
            let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend())
            let session = DisplaySession(provider: provider, capture: ScreenCaptureKitSource(), configuration: configuration, captureEnabled: false)
            Signals.keepSession = session
            host = DisplayStreamHost(session: session)
        }

        let server = StreamServer(host: host, settings: configuration.streaming)
        server.requireLoopbackToken(LoopbackToken.generate())  // handed to the tablet over adb
        try server.start()
        Signals.keepServer = server
        print("Tab2Mac server on 127.0.0.1:\(configuration.streaming.port) (\(arguments.flags.contains("synthetic") ? "synthetic pattern" : "virtual display")), codec \(configuration.streaming.codec.rawValue), \(configuration.streaming.bitrateKbps) kbps")
        print(server.status.adbAvailable ? "adb found: keeping `adb reverse tcp:\(configuration.streaming.port) tcp:\(configuration.streaming.port)` on every authorised tablet" : "adb not found: run `adb reverse tcp:\(configuration.streaming.port) tcp:\(configuration.streaming.port)` yourself")
        print("Press Ctrl-C to stop.")

        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler {
            Task { @MainActor in
                server.stop()
                if let session = Signals.keepSession { await session.stopDisplay() }
                print("stopped")
                exit(0)
            }
        }
        interrupt.resume()
        Signals.keepAlive = interrupt

        var lastLine = ""
        while true {
            try? await Task.sleep(for: .seconds(1))
            server.refresh()
            let status = server.status
            let devices = status.adbDevices.filter(\.isReady).map { $0.model ?? $0.serial }.joined(separator: ", ")
            var line = "adb: [\(devices)]"
            if let connection = status.connection {
                line += " | \(connection.clientModel ?? connection.endpoint) \(connection.phase.rawValue) \(connection.codec?.rawValue ?? "")"
                line += String(format: " | sent %d (key %d) | %.1f Mbps | skipped %d", connection.framesSent, connection.keyframesSent, connection.sentKilobitsPerSecond / 1000, connection.framesSkippedForBackpressure)
                if let encode = connection.encodeMilliseconds { line += String(format: " | encode p50 %.1f ms", encode.p50) }
                if let report = connection.lastReport {
                    if let e2e = report.endToEndMs { line += String(format: " | e2e p50 %.1f / p95 %.1f ms", e2e.p50, e2e.p95) }
                    if let decode = report.decodeMs { line += String(format: " | decode p50 %.1f ms", decode.p50) }
                    if let rtt = report.rttUs { line += " | rtt \(rtt) µs" }
                }
            } else {
                line += " | waiting for the tablet"
            }
            if line != lastLine {
                print(line)
                lastLine = line
            }
        }
    }

    // MARK: Output

    static func printJSON(_ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) {
            print(String(decoding: data, as: UTF8.self))
        }
    }

    static func writeJSON(_ value: some Encodable, to path: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

@MainActor
extension Commands {
    // MARK: run (headless)

    @MainActor
    static func runHeadless(_ arguments: Arguments) async throws -> Int32 {
        let configuration: Tab2MacConfiguration
        if let path = arguments.options["config"] {
            configuration = try JSONDecoder().decode(Tab2MacConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)))
            try configuration.validate()
        } else {
            configuration = try ConfigurationStore().load()
        }
        let runtime = Tab2MacRuntime(configuration: configuration, pairingPresenter: TerminalPairingPrompt.present)
        try runtime.start(serveUSB: !arguments.flags.contains("no-adb"))
        Signals.keepRuntime = runtime
        print("Tab2Mac running headless (\(runtime.backendIdentifier)). Direct USB: \(configuration.streaming.directUSB ? "on" : "off") · adb: \(arguments.flags.contains("no-adb") ? "off" : "on") · Wi‑Fi: \(configuration.streaming.wifi ? "on" : "off"). Ctrl-C to quit.")

        // Event-driven status: a line when something changes, nothing while idle.
        let server = runtime.server
        var lastLine = ""
        server.onChange = {
            server.refresh()
            let line = server.status.connection.map { "tablet: \($0.clientModel ?? $0.endpoint) \($0.phase.rawValue)" } ?? "waiting for a tablet"
            if line != lastLine {
                print(line)
                lastLine = line
            }
        }
        if arguments.flags.contains("direct") {
            runtime.direct.onChange = { state in print("direct: \(state)") }
            Task { await runtime.direct.start() }
        }

        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated {
                    runtime.shutdown()
                    print("stopped")
                    exit(0)
                }
            }
            source.resume()
            Signals.keepSources.append(source)
        }
        // Runs until a signal: the continuation is kept (never resumed) so it isn't reported as leaked.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in Signals.forever = continuation }
        return 0
    }
}

/// Wi‑Fi pairing in a terminal: the code is shown, and the user answers y/n.
@MainActor
enum TerminalPairingPrompt {
    static func present(_ request: PairingRequest) {
        let code = request.code.prefix(3) + " " + request.code.suffix(3)
        print("Pair with “\(request.tabletName)”? The tablet must show \(code). [y/N]")
        request.onEnd { print("pairing withdrawn") }
        DispatchQueue.global().async {
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
            request.respond(answer == "y" || answer == "yes")
        }
    }
}

@MainActor
enum Signals {
    static var keepRuntime: Tab2MacRuntime?
    static var keepSources: [any DispatchSourceSignal] = []
    static var forever: CheckedContinuation<Void, Never>?
    static var keepAlive: (any DispatchSourceSignal)?
    static var keepServer: StreamServer?
    static var keepSession: DisplaySession?
}
