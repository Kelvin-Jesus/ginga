import AppKit
import CoreGraphics
import CoreVideo
import DisplayCapture
import Foundation
import ImageIO
import Tab2MacCore
import UniformTypeIdentifiers
import VideoToolbox

/// Facts about the machine, recorded in every report so results stay comparable.
public struct HostInfo: Codable, Hashable, Sendable {
    public var macOSVersion: String
    public var model: String
    public var chip: String
    public var memoryGigabytes: Double
    public var processorCount: Int

    public static func current() -> HostInfo {
        HostInfo(
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: sysctlString("hw.model") ?? "unknown",
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            memoryGigabytes: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
            processorCount: ProcessInfo.processInfo.processorCount
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

/// One sample of process/GPU resource usage.
public struct ResourceSample: Codable, Hashable, Sendable {
    public var cpuPercent: Double
    public var memoryFootprintMegabytes: Double
    public var gpuDevicePercent: Double?
}

/// Samples CPU (process), memory footprint (process) and GPU utilisation (system-wide).
public struct ResourceSampler: Sendable {
    private var cpu = CPUUsageSampler()

    public init() {
        _ = cpu.sample()
    }

    public mutating func sample() -> ResourceSample {
        ResourceSample(
            cpuPercent: cpu.sample(),
            memoryFootprintMegabytes: Double(ProcessMetrics.memoryFootprintBytes() ?? 0) / 1_048_576,
            gpuDevicePercent: GPUUtilization.read()?.devicePercent
        )
    }
}

/// Public-API views of a display, used for verification and diagnostics.
@MainActor
public enum DisplayInspection {
    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }
    }

    /// AppKit learns about a new display a moment after CoreGraphics does: waits (briefly) for
    /// its NSScreen. For benchmarks and checks; the app reacts to screen-change notifications.
    public static func waitForScreen(_ displayID: CGDirectDisplayID, timeout: Duration = .seconds(3)) async -> NSScreen? {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if let screen = screen(for: displayID) { return screen }
            guard ContinuousClock.now < deadline else { return nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    public static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Display names as System Information lists them (the same list System Settings shows).
    nonisolated public static func systemProfilerDisplayNames() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPDisplaysDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard
                    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let gpus = root["SPDisplaysDataType"] as? [[String: Any]]
                else { return [] }
                return gpus.flatMap { ($0["spdisplays_ndrvs"] as? [[String: Any]] ?? []).compactMap { $0["_name"] as? String } }
            } catch {
                return []
            }
        }.value
    }
}

public enum FrameSnapshot {
    public enum SnapshotError: Error {
        case conversionFailed(OSStatus)
        case writeFailed(URL)
    }

    /// Writes a captured frame (any format VideoToolbox can convert, including 420v) as PNG.
    public static func writePNG(_ pixelBuffer: CVPixelBuffer, to url: URL) throws {
        var image: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard status == noErr, let image else { throw SnapshotError.conversionFailed(status) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SnapshotError.writeFailed(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotError.writeFailed(url) }
    }
}
