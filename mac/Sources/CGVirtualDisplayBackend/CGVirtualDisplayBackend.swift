import CGVirtualDisplayShim
import CoreGraphics
import Foundation
import Tab2MacCore
import VirtualDisplay

/// Path A — the private CoreGraphics `CGVirtualDisplay` API.
///
/// Every private call goes through `T2MPrivateVirtualDisplay` (Objective-C), which verifies the
/// runtime interface first and turns exceptions into errors. This type only translates between
/// the backend protocol's value types and the shim. Not suitable for the Mac App Store.
@MainActor
public final class CGVirtualDisplayBackend: VirtualDisplayBackend {
    public let identifier = "cgvirtualdisplay-private"

    private let classResolver: T2MClassResolver?
    private var display: T2MPrivateVirtualDisplay?

    /// - Parameter classResolver: test hook to substitute the private classes; nil resolves the
    ///   real ones by name at runtime.
    public init(classResolver: T2MClassResolver? = nil) {
        self.classResolver = classResolver
    }

    public func availability() -> BackendAvailability {
        let report = privateAPIReport()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        guard report.isUsable else {
            return .unavailable(reason: "private CGVirtualDisplay API is not usable on macOS \(os)", details: report.problems)
        }
        var summary = "private CGVirtualDisplay API verified on macOS \(os)"
        if !report.missingOptional.isEmpty {
            summary += " (optional features missing: \(report.missingOptional.joined(separator: "; ")))"
        }
        return .available(summary: summary)
    }

    /// Full verification report (for `t2m probe` and diagnostics).
    public func privateAPIReport() -> T2MPrivateAPIReport {
        classResolver.map { T2MPrivateAPIChecker.check(classResolver: $0) } ?? T2MPrivateAPIChecker.checkRuntime()
    }

    public var displayID: CGDirectDisplayID? {
        guard let display, display.isValid else { return nil }
        return display.displayID
    }

    public func createDisplay(
        _ descriptor: VirtualDisplayDescriptor,
        modes: VirtualDisplayModeSet,
        onTermination: @escaping @MainActor () -> Void
    ) throws -> CGDirectDisplayID {
        guard display == nil else { throw VirtualDisplayBackendError.alreadyCreated }

        let spec = T2MVirtualDisplaySpec()
        spec.name = descriptor.name
        spec.vendorID = descriptor.identity.vendorID
        spec.productID = descriptor.identity.productID
        spec.serialNumber = descriptor.identity.serialNumber
        spec.maxPixelsWide = UInt32(clamping: descriptor.maxPixels.width)
        spec.maxPixelsHigh = UInt32(clamping: descriptor.maxPixels.height)
        spec.sizeInMillimeters = CGSize(width: descriptor.physicalSize.widthMillimeters, height: descriptor.physicalSize.heightMillimeters)
        if let primaries = descriptor.colorPrimaries {
            spec.hasColorPrimaries = true
            spec.redPrimary = CGPoint(x: primaries.red.x, y: primaries.red.y)
            spec.greenPrimary = CGPoint(x: primaries.green.x, y: primaries.green.y)
            spec.bluePrimary = CGPoint(x: primaries.blue.x, y: primaries.blue.y)
            spec.whitePoint = CGPoint(x: primaries.whitePoint.x, y: primaries.whitePoint.y)
        }

        // Invoked on the main queue by the shim; hop through a task so isolation never depends on it.
        let terminationHandler: () -> Void = {
            Task { @MainActor in onTermination() }
        }

        do {
            let created: T2MPrivateVirtualDisplay
            if let classResolver {
                created = try T2MPrivateVirtualDisplay(
                    spec: spec, modes: Self.shimModes(modes), hiDPI: modes.hiDPI,
                    terminationHandler: terminationHandler, classResolver: classResolver
                )
            } else {
                created = try T2MPrivateVirtualDisplay(
                    spec: spec, modes: Self.shimModes(modes), hiDPI: modes.hiDPI,
                    terminationHandler: terminationHandler
                )
            }
            display = created
            return created.displayID
        } catch {
            throw Self.map(error, applyingSettings: false)
        }
    }

    public func setDisplayModes(_ modes: VirtualDisplayModeSet) throws {
        guard let display, display.isValid else { throw VirtualDisplayBackendError.noDisplay }
        do {
            try display.applyModes(Self.shimModes(modes), hiDPI: modes.hiDPI)
        } catch {
            throw Self.map(error, applyingSettings: true)
        }
    }

    public func destroyDisplay() {
        display?.invalidate()
        display = nil
    }

    private static func shimModes(_ modes: VirtualDisplayModeSet) -> [T2MVirtualDisplayModeSpec] {
        modes.modes.map {
            T2MVirtualDisplayModeSpec(width: UInt32(clamping: $0.size.width), height: UInt32(clamping: $0.size.height), refreshRate: $0.refreshRate)
        }
    }

    private static func map(_ error: any Error, applyingSettings: Bool) -> VirtualDisplayBackendError {
        guard let error = error as? T2MPrivateDisplayError else {
            return applyingSettings ? .settingsRejected(error.localizedDescription) : .creationFailed(error.localizedDescription)
        }
        let message = error.localizedDescription
        switch error.code {
        case .unavailable: return .unavailable(message)
        case .settingsRejected: return .settingsRejected(message)
        case .invalidated: return .noDisplay
        case .creationFailed: return .creationFailed(message)
        case .exception: return applyingSettings ? .settingsRejected(message) : .creationFailed(message)
        @unknown default: return .creationFailed(message)
        }
    }
}
