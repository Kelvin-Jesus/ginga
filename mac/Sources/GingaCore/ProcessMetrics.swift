import Darwin
import Foundation
import IOKit

/// Point-in-time resource usage of the current process.
public enum ProcessMetrics {
    /// Physical footprint in bytes — the figure Activity Monitor reports as "Memory".
    public static func memoryFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// Total user + system CPU time consumed by this process so far.
    public static func cpuTime() -> Duration {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return .seconds(Int64(usage.ru_utime.tv_sec) + Int64(usage.ru_stime.tv_sec))
            + .microseconds(Int64(usage.ru_utime.tv_usec) + Int64(usage.ru_stime.tv_usec))
    }
}

/// Measures process CPU usage between successive `sample()` calls. 100% = one fully busy core.
public struct CPUUsageSampler: Sendable {
    private var lastCPU: Duration?
    private var lastWall: MediaTime?

    public init() {}

    public mutating func sample(now: MediaTime = .now()) -> Double {
        let cpu = ProcessMetrics.cpuTime()
        defer {
            lastCPU = cpu
            lastWall = now
        }
        guard let lastCPU, let lastWall, now > lastWall else { return 0 }
        return (cpu - lastCPU).inSeconds / (now - lastWall).inSeconds * 100
    }
}

/// System-wide GPU utilisation as published by the Apple GPU driver in the IORegistry.
///
/// There is no public per-process GPU metric on macOS; this is the same data `ioreg` shows under
/// `IOAccelerator` → `PerformanceStatistics`, readable without privileges.
public struct GPUUtilization: Hashable, Sendable, Codable {
    public var devicePercent: Double
    public var rendererPercent: Double?
    public var tilerPercent: Double?

    public static func read() -> GPUUtilization? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard
                let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
                let statistics = property.takeRetainedValue() as? [String: Any],
                let device = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue
            else { continue }
            return GPUUtilization(
                devicePercent: device,
                rendererPercent: (statistics["Renderer Utilization %"] as? NSNumber)?.doubleValue,
                tilerPercent: (statistics["Tiler Utilization %"] as? NSNumber)?.doubleValue
            )
        }
        return nil
    }
}
