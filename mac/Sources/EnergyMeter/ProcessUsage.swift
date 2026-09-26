import Darwin
import Foundation
import Tab2MacCore

/// Cumulative CPU time, energy and wake-ups of one process.
///
/// `proc_pid_rusage` (public) covers processes of the same user, which includes Tab2Mac and
/// replayd (ScreenCaptureKit's capture daemon). Other users' processes, such as WindowServer,
/// only expose CPU time, which is read through `ps`.
public struct ProcessUsage: Codable, Sendable, Equatable {
    public var cpuSeconds: Double
    public var energyJoules: Double?
    public var wakeups: UInt64?

    public init(cpuSeconds: Double, energyJoules: Double? = nil, wakeups: UInt64? = nil) {
        self.cpuSeconds = cpuSeconds
        self.energyJoules = energyJoules
        self.wakeups = wakeups
    }

    public static func read(pid: pid_t) -> ProcessUsage? {
        var info = rusage_info_v6()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        if status == 0 {
            let nanoseconds = HostTimebase.current.nanoseconds(fromTicks: info.ri_user_time + info.ri_system_time)
            return ProcessUsage(
                cpuSeconds: Double(nanoseconds) / 1e9,
                energyJoules: Double(info.ri_energy_nj) / 1e9,
                wakeups: info.ri_interrupt_wkups + info.ri_pkg_idle_wkups
            )
        }
        return psCPUSeconds(pid: pid).map { ProcessUsage(cpuSeconds: $0) }
    }

    /// `ps -o time=` prints `[hours:]minutes:seconds.centiseconds`.
    static func parseCPUTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds
    }

    private static func psCPUSeconds(pid: pid_t) -> Double? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "time=", "-p", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseCPUTime(String(decoding: data, as: UTF8.self))
    }

    /// Process IDs whose executable name is `name` (the kernel keeps the first 16 characters).
    /// Uses `sysctl(KERN_PROC_ALL)`, which, unlike `proc_name`, covers other users' processes.
    public static func pids(named name: String) -> [pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = processes.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else { return [] }
        let wanted = String(name.prefix(Int(MAXCOMLEN)))
        return processes.prefix(size / MemoryLayout<kinfo_proc>.stride).compactMap { process in
            let command = withUnsafeBytes(of: process.kp_proc.p_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return command == wanted ? process.kp_proc.p_pid : nil
        }
    }
}

/// Rates over a measurement window.
public struct ProcessRates: Codable, Sendable, Equatable {
    /// Percent of one core.
    public var cpuPercent: Double
    public var milliwatts: Double?
    public var wakeupsPerSecond: Double?

    public init(from start: ProcessUsage, to end: ProcessUsage, seconds: Double) {
        let seconds = max(seconds, .leastNonzeroMagnitude)
        cpuPercent = max(0, end.cpuSeconds - start.cpuSeconds) / seconds * 100
        if let a = start.energyJoules, let b = end.energyJoules { milliwatts = max(0, b - a) / seconds * 1000 }
        if let a = start.wakeups, let b = end.wakeups, b >= a { wakeupsPerSecond = Double(b - a) / seconds }
    }

    public init(cpuPercent: Double, milliwatts: Double? = nil, wakeupsPerSecond: Double? = nil) {
        self.cpuPercent = cpuPercent
        self.milliwatts = milliwatts
        self.wakeupsPerSecond = wakeupsPerSecond
    }
}
