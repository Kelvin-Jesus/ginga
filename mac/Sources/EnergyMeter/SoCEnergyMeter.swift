import CoreFoundation
import Darwin
import Foundation
import Tab2MacCore

/// System-wide SoC energy from IOReport's "Energy Model" channels (the counters behind
/// `powermetrics`), readable without root.
///
/// IOReport is a private framework. As with the virtual-display shim, it is resolved at runtime,
/// every symbol is checked and a failure is an error, never a crash. Only the developer CLI links
/// this module (for benchmarks); the app never does.
public final class SoCEnergyMeter: @unchecked Sendable {  // immutable after init; sampling is thread-safe
    public enum Unavailable: Error, CustomStringConvertible {
        case library(String)
        case symbol(String)
        case channels
        case subscription

        public var description: String {
            switch self {
            case .library(let reason): "IOReport not loadable: \(reason)"
            case .symbol(let name): "IOReport symbol missing: \(name)"
            case .channels: "IOReport has no \"Energy Model\" channels on this Mac"
            case .subscription: "IOReport subscription failed"
            }
        }
    }

    /// A cumulative reading; energy is the difference between two.
    public struct Reading: @unchecked Sendable {  // wraps an immutable CFDictionary
        fileprivate let samples: CFDictionary
        public let time: MediaTime
    }

    public struct Channel: Codable, Sendable, Hashable {
        public let name: String
        public let joules: Double

        public init(name: String, joules: Double) {
            self.name = name
            self.joules = joules
        }
    }

    private typealias CopyChannelsInGroup = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFDictionary>?
    private typealias CreateSubscription = @convention(c) (
        UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, CFTypeRef?
    ) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary?, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias SimpleGetIntegerValue = @convention(c) (CFDictionary, UnsafeMutablePointer<Int32>?) -> Int64
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?

    private let createSamples: CreateSamples
    private let createDelta: CreateSamplesDelta
    private let integerValue: SimpleGetIntegerValue
    private let channelName: ChannelString
    private let unitLabel: ChannelString
    private let subscription: OpaquePointer
    private let subscribed: CFMutableDictionary

    public init(libraryPath: String = "/usr/lib/libIOReport.dylib") throws(Unavailable) {
        guard let handle = dlopen(libraryPath, RTLD_NOW) else {
            throw .library(dlerror().map { String(cString: $0) } ?? libraryPath)
        }
        func symbol<T>(_ name: String, as type: T.Type) throws(Unavailable) -> T {
            guard let pointer = dlsym(handle, name) else { throw .symbol(name) }
            return unsafeBitCast(pointer, to: type)
        }
        let copyChannels = try symbol("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self)
        let createSubscription = try symbol("IOReportCreateSubscription", as: CreateSubscription.self)
        createSamples = try symbol("IOReportCreateSamples", as: CreateSamples.self)
        createDelta = try symbol("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self)
        integerValue = try symbol("IOReportSimpleGetIntegerValue", as: SimpleGetIntegerValue.self)
        channelName = try symbol("IOReportChannelGetChannelName", as: ChannelString.self)
        unitLabel = try symbol("IOReportChannelGetUnitLabel", as: ChannelString.self)

        guard let channels = copyChannels("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue(),
              let desired = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels) else { throw .channels }
        var subscribedOut: Unmanaged<CFMutableDictionary>?
        // Ownership of the out-parameter is undocumented: take it unretained (a CLI-lifetime leak at
        // worst, never an over-release).
        guard let subscription = createSubscription(nil, desired, &subscribedOut, 0, nil),
              let subscribed = subscribedOut?.takeUnretainedValue() else { throw .subscription }
        self.subscription = subscription
        self.subscribed = subscribed
    }

    public func read() -> Reading? {
        guard let samples = createSamples(subscription, subscribed, nil)?.takeRetainedValue() else { return nil }
        return Reading(samples: samples, time: .now())
    }

    /// Energy per channel between two readings.
    public func channels(from start: Reading, to end: Reading) -> [Channel] {
        guard let delta = createDelta(start.samples, end.samples, nil)?.takeRetainedValue(),
              let items = (delta as NSDictionary)["IOReportChannels"] as? [NSDictionary] else { return [] }
        return items.compactMap { item in
            let channel = item as CFDictionary
            guard let name = channelName(channel)?.takeUnretainedValue() as String?,
                  let scale = Self.joulesPerUnit(unitLabel(channel)?.takeUnretainedValue() as String?) else { return nil }
            return Channel(name: name, joules: Double(integerValue(channel, nil)) * scale)
        }
    }

    static func joulesPerUnit(_ label: String?) -> Double? {
        switch label?.trimmingCharacters(in: .whitespaces) {
        case "J": 1
        case "mJ": 1e-3
        case "uJ", "µJ": 1e-6
        case "nJ": 1e-9
        default: nil
        }
    }
}

/// Average power of the SoC blocks the pipeline touches, from IOReport channels.
public struct EnergyBreakdown: Codable, Sendable, Equatable {
    public var seconds: Double
    /// Milliwatts per block.
    public var cpu = 0.0
    public var gpu = 0.0
    /// AVE, the hardware video encoder.
    public var encoder = 0.0
    /// VDEC/AVD, the hardware video decoder.
    public var decoder = 0.0
    /// DRAM plus the memory fabric (AMCC, DCS): frame copies and conversions show up here.
    public var memory = 0.0
    /// MSR, the scaler/rotator block.
    public var scaler = 0.0
    /// Display pipes (the built-in panel and external monitors, not the virtual display).
    public var display = 0.0
    public var other = 0.0
    public var total = 0.0

    enum Block { case cpu, gpu, encoder, decoder, memory, scaler, display, other, component }

    public init(seconds: Double) {
        self.seconds = seconds
    }

    public init(channels: [SoCEnergyMeter.Channel], seconds: Double) {
        self.seconds = seconds
        guard seconds > 0 else { return }
        for channel in channels {
            let milliwatts = channel.joules / seconds * 1000
            switch Self.block(for: channel.name) {
            case .cpu: cpu += milliwatts
            case .gpu: gpu += milliwatts
            case .encoder: encoder += milliwatts
            case .decoder: decoder += milliwatts
            case .memory: memory += milliwatts
            case .scaler: scaler += milliwatts
            case .display: display += milliwatts
            case .other: other += milliwatts
            case .component: continue
            }
        }
        total = cpu + gpu + encoder + decoder + memory + scaler + display + other
    }

    /// Totals are taken from the aggregate channels; per-core, per-cluster and DTL channels are
    /// parts of them and skipped.
    static func block(for name: String) -> Block {
        switch name {
        case "CPU Energy": return .cpu
        case "GPU Energy", "GPU SRAM": return .gpu
        default: break
        }
        if name.hasPrefix("AVE") { return .encoder }
        if name.hasPrefix("VDEC") || name.hasPrefix("AVD") { return .decoder }
        if name.hasPrefix("DRAM") || name.hasPrefix("AMCC") || name.hasPrefix("DCS") { return .memory }
        if name.hasPrefix("MSR") { return .scaler }
        if name.hasPrefix("DISP") { return .display }
        if name.contains("CPU") || name.hasPrefix("ECPM") || name.hasPrefix("PCPM") || name.hasPrefix("EACC") || name.hasPrefix("PACC") || name.hasPrefix("GPU") {
            return .component
        }
        return .other
    }

    /// Element-wise difference, e.g. a scenario minus the idle baseline.
    public static func - (lhs: EnergyBreakdown, rhs: EnergyBreakdown) -> EnergyBreakdown {
        var result = EnergyBreakdown(seconds: lhs.seconds)
        result.cpu = lhs.cpu - rhs.cpu
        result.gpu = lhs.gpu - rhs.gpu
        result.encoder = lhs.encoder - rhs.encoder
        result.decoder = lhs.decoder - rhs.decoder
        result.memory = lhs.memory - rhs.memory
        result.scaler = lhs.scaler - rhs.scaler
        result.display = lhs.display - rhs.display
        result.other = lhs.other - rhs.other
        result.total = lhs.total - rhs.total
        return result
    }

    /// Mean of several measurements (repeats of one scenario).
    public static func mean(_ values: [EnergyBreakdown]) -> EnergyBreakdown? {
        guard !values.isEmpty else { return nil }
        let n = Double(values.count)
        var result = EnergyBreakdown(seconds: values.map(\.seconds).reduce(0, +) / n)
        result.cpu = values.map(\.cpu).reduce(0, +) / n
        result.gpu = values.map(\.gpu).reduce(0, +) / n
        result.encoder = values.map(\.encoder).reduce(0, +) / n
        result.decoder = values.map(\.decoder).reduce(0, +) / n
        result.memory = values.map(\.memory).reduce(0, +) / n
        result.scaler = values.map(\.scaler).reduce(0, +) / n
        result.display = values.map(\.display).reduce(0, +) / n
        result.other = values.map(\.other).reduce(0, +) / n
        result.total = values.map(\.total).reduce(0, +) / n
        return result
    }
}
