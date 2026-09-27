import AppKit
import CoreGraphics
import DisplayCapture
import Foundation
import os
import GingaCore
import VirtualDisplay

public struct ResourceSummary: Codable, Hashable, Sendable {
    public var cpuPercent: StatisticSummary?
    public var memoryFootprintMegabytes: StatisticSummary?
    public var gpuDevicePercent: StatisticSummary?

    public init(_ samples: [ResourceSample]) {
        func summarize(_ values: [Double]) -> StatisticSummary? {
            var window = SampleWindow(capacity: max(values.count, 1))
            values.forEach { window.add($0) }
            return window.summary
        }
        cpuPercent = summarize(samples.map(\.cpuPercent))
        memoryFootprintMegabytes = summarize(samples.map(\.memoryFootprintMegabytes))
        gpuDevicePercent = summarize(samples.compactMap(\.gpuDevicePercent))
    }
}

public struct CaptureBenchmarkReport: Codable, Sendable {
    public struct DisplaySummary: Codable, Hashable, Sendable {
        public var displayID: UInt32
        public var mode: String
        public var pixelSize: PixelSize
        public var refreshRate: Double
    }

    public struct CaptureSummary: Codable, Hashable, Sendable {
        public var outputSize: PixelSize
        public var pixelFormat: String
        public var queueDepth: Int
        public var minimumFrameIntervalSeconds: Double
    }

    public var benchmark = "capture"
    public var date: Date
    public var host: HostInfo
    public var backend: String
    public var display: DisplaySummary
    public var capture: CaptureSummary
    public var baselineSeconds: Double
    public var captureSeconds: Double
    /// Display + animated load window, no capture: what the system costs without us.
    public var baseline: ResourceSummary
    /// Same, plus capture of every frame.
    public var capturing: ResourceSummary
    public var statistics: CaptureStatisticsSnapshot
    public var averageFramesPerSecond: Double
    public var framesDeliveredToSink: Int

    public var summary: String {
        func fmt(_ summary: StatisticSummary?, _ unit: String) -> String {
            guard let summary else { return "n/a" }
            return String(format: "mean %.1f%@ p95 %.1f%@", summary.mean, unit, summary.p95, unit)
        }
        return """
        Capture benchmark — \(host.model), macOS \(host.macOSVersion)
        display \(display.displayID): \(display.mode) → capture \(capture.outputSize) \(capture.pixelFormat)
        frames: \(statistics.completeFrames) in \(captureSeconds)s = \(String(format: "%.1f", averageFramesPerSecond)) fps avg
        frame interval: \(fmt(statistics.frameIntervalMilliseconds, "ms"))
        delivery vs display time (negative = before its vsync): \(fmt(statistics.captureLatencyMilliseconds, "ms"))
        CPU (process): baseline \(fmt(baseline.cpuPercent, "%")) → capturing \(fmt(capturing.cpuPercent, "%"))
        memory (process): baseline \(fmt(baseline.memoryFootprintMegabytes, "MB")) → capturing \(fmt(capturing.memoryFootprintMegabytes, "MB"))
        GPU (system): baseline \(fmt(baseline.gpuDevicePercent, "%")) → capturing \(fmt(capturing.gpuDevicePercent, "%"))
        """
    }
}

public enum BenchmarkError: Error, CustomStringConvertible {
    case permissionDenied
    case display(String)
    case capture(String)

    public var description: String {
        switch self {
        case .permissionDenied: "Screen Recording permission is required for the capture benchmark"
        case .display(let reason): "virtual display: \(reason)"
        case .capture(let reason): "capture: \(reason)"
        }
    }
}

/// Measures capture of a continuously animating virtual display: frame rate, pacing, capture
/// latency, and the process CPU / memory and system GPU cost relative to a no-capture baseline.
@MainActor
public final class CaptureBenchmark {
    private let provider: VirtualDisplayProvider
    private let capture: any DisplayCaptureSource

    public init(provider: VirtualDisplayProvider, capture: any DisplayCaptureSource) {
        self.provider = provider
        self.capture = capture
    }

    public func run(
        configuration: GingaConfiguration,
        baselineSeconds: Double = 3,
        captureSeconds: Double = 10
    ) async throws(BenchmarkError) -> CaptureBenchmarkReport {
        guard ScreenCapturePermission.isGranted else { throw .permissionDenied }
        let active: ActiveVirtualDisplay
        do {
            active = try await provider.start(configuration.display)
        } catch {
            throw .display(error.description)
        }

        let load = LoadGenerator()
        if let screen = await DisplayInspection.waitForScreen(active.displayID) {
            load.start(on: screen, title: "Ginga capture benchmark")
        } else {
            Log.benchmark.error("benchmark.no-screen display=\(active.displayID) — measuring without the animated load")
        }
        try? await Task.sleep(for: .milliseconds(500))
        let baseline = await sample(for: baselineSeconds)

        let captureConfiguration = configuration.capture.captureConfiguration(for: active)
        let delivered = LockedValue(0)
        do {
            try await capture.start(
                displayID: active.displayID,
                configuration: captureConfiguration,
                onFrame: { _ in delivered.update { $0 += 1 } },
                onStop: { error in Log.benchmark.error("benchmark.capture-stopped reason=\(error.description, privacy: .public)") }
            )
        } catch {
            load.stop()
            await provider.stop()
            throw .capture(error.description)
        }
        let started = MediaTime.now()
        let capturing = await sample(for: captureSeconds)
        let elapsed = (MediaTime.now() - started).inSeconds
        let statistics = capture.statistics
        await capture.stop()
        load.stop()
        await provider.stop()

        let outputSize = CaptureSizing.outputSize(displayPixels: active.pixelSize, maxOutputSize: captureConfiguration.maxOutputSize)
        let report = CaptureBenchmarkReport(
            date: Date(),
            host: .current(),
            backend: provider.backendIdentifier,
            display: .init(displayID: active.displayID, mode: active.mode?.description ?? "unknown", pixelSize: active.pixelSize, refreshRate: active.mode?.refreshRate ?? configuration.display.refreshRate),
            capture: .init(outputSize: outputSize, pixelFormat: captureConfiguration.pixelFormat.rawValue, queueDepth: captureConfiguration.queueDepth, minimumFrameIntervalSeconds: captureConfiguration.minimumFrameInterval.seconds),
            baselineSeconds: baselineSeconds,
            captureSeconds: elapsed,
            baseline: ResourceSummary(baseline),
            capturing: ResourceSummary(capturing),
            statistics: statistics,
            averageFramesPerSecond: Double(statistics.completeFrames) / max(elapsed, 0.001),
            framesDeliveredToSink: delivered.value
        )
        Log.benchmark.info("benchmark.capture fps=\(report.averageFramesPerSecond) frames=\(statistics.completeFrames)")
        return report
    }

    private func sample(for seconds: Double) async -> [ResourceSample] {
        var sampler = ResourceSampler()
        var samples: [ResourceSample] = []
        let deadline = MediaTime.now().advanced(by: .milliseconds(Int64(seconds * 1000)))
        while MediaTime.now() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            samples.append(sampler.sample())
        }
        return samples
    }
}
