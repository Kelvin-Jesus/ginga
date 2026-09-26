import Foundation
import IOKit.ps

/// Whether the Mac runs on battery, and a notification when that changes (IOKit power sources,
/// event-driven: nothing polls).
public enum PowerSource {
    public static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

/// Calls `onChange` on the main run loop whenever the power source changes (AC ↔ battery).
@MainActor
public final class PowerSourceMonitor {
    /// Set on the main actor; also read by `deinit`, which runs once nothing else holds the
    /// monitor. CFRunLoop calls are thread-safe.
    nonisolated(unsafe) private var source: CFRunLoopSource?
    private let onChange: @MainActor (Bool) -> Void
    private var lastOnBattery = PowerSource.isOnBattery

    public init(onChange: @escaping @MainActor (_ onBattery: Bool) -> Void) {
        self.onChange = onChange
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.changed() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    /// Stops notifications. Also done on release: the run-loop source holds an unretained
    /// pointer to the monitor, so it must never outlive it.
    public func invalidate() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func changed() {
        let onBattery = PowerSource.isOnBattery
        guard onBattery != lastOnBattery else { return }  // fires for charge-level updates too
        lastOnBattery = onBattery
        onChange(onBattery)
    }
}
