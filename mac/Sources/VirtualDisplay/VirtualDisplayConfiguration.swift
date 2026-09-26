import Foundation
import Tab2MacCore

public enum DisplayOrientation: String, Codable, Sendable, CaseIterable {
    case landscape
    case portrait
}

/// EDID-style identity. macOS remembers arrangement and settings per identity, like a real monitor.
public struct DisplayIdentity: Hashable, Sendable, Codable {
    public var vendorID: UInt32
    public var productID: UInt32
    public var serialNumber: UInt32

    public init(vendorID: UInt32, productID: UInt32, serialNumber: UInt32) {
        self.vendorID = vendorID
        self.productID = productID
        self.serialNumber = serialNumber
    }

    /// 0x5022 is the packed EDID manufacturer code "TAB"; no macOS display override exists for it.
    public static let tab2macVendorID: UInt32 = 0x5022
}

/// Where the display sits relative to the main display, in the same sense as System Settings › Displays.
public struct DisplayArrangement: Hashable, Sendable, Codable {
    public enum Placement: String, Codable, Sendable, CaseIterable {
        /// Leave placement to macOS (it remembers the last arrangement for this display identity).
        case automatic
        case left, right, above, below
    }

    /// Alignment along the shared edge: `start` = top (left/right placement) or left (above/below).
    public enum Alignment: String, Codable, Sendable, CaseIterable {
        case start, center, end
    }

    public var placement: Placement
    public var alignment: Alignment

    public init(placement: Placement, alignment: Alignment) {
        self.placement = placement
        self.alignment = alignment
    }

    public static let automatic = DisplayArrangement(placement: .automatic, alignment: .start)

    enum CodingKeys: String, CodingKey { case placement, alignment }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placement = try container.decodeIfPresent(Placement.self, forKey: .placement) ?? .automatic
        alignment = try container.decodeIfPresent(Alignment.self, forKey: .alignment) ?? .start
    }
}

/// The physical panel of the receiving device, always described in landscape.
public struct PanelSpecification: Hashable, Sendable, Codable {
    public var nativePixels: PixelSize
    public var physicalSize: PhysicalSize
    public var maxRefreshRate: Double

    public init(nativePixels: PixelSize, physicalSize: PhysicalSize, maxRefreshRate: Double) {
        self.nativePixels = nativePixels
        self.physicalSize = physicalSize
        self.maxRefreshRate = maxRefreshRate
    }
}

/// Everything the Virtual Display Provider needs to create and configure one display.
///
/// Sizes are *logical* ("looks like") sizes in landscape orientation; the planner derives the
/// oriented modes and pixel sizes. Decoding starts from a device profile and applies overrides,
/// so configuration files only need the fields they change.
public struct VirtualDisplayConfiguration: Hashable, Sendable {
    public var profileID: String?
    public var name: String
    public var identity: DisplayIdentity
    public var panel: PanelSpecification
    /// The selected "looks like" resolution (landscape-referenced).
    public var resolution: PointSize
    /// Render at 2× (Retina). When false, one pixel per point.
    public var hiDPI: Bool
    public var refreshRate: Double
    public var orientation: DisplayOrientation
    public var arrangement: DisplayArrangement
    /// Additional resolutions offered in System Settings › Displays (landscape-referenced).
    public var extraResolutions: [PointSize]

    public init(
        profileID: String?,
        name: String,
        identity: DisplayIdentity,
        panel: PanelSpecification,
        resolution: PointSize,
        hiDPI: Bool,
        refreshRate: Double,
        orientation: DisplayOrientation,
        arrangement: DisplayArrangement,
        extraResolutions: [PointSize]
    ) {
        self.profileID = profileID
        self.name = name
        self.identity = identity
        self.panel = panel
        self.resolution = resolution
        self.hiDPI = hiDPI
        self.refreshRate = refreshRate
        self.orientation = orientation
        self.arrangement = arrangement
        self.extraResolutions = extraResolutions
    }

    public static let supportedPointRange = 320...8192
    public static let maxPixelDimension = 8192
    public static let supportedRefreshRates = 1.0...240.0

    public func validate() throws(VirtualDisplayConfigurationError) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyName }
        for size in [resolution] + extraResolutions {
            guard Self.supportedPointRange.contains(size.width), Self.supportedPointRange.contains(size.height) else {
                throw .resolutionOutOfRange(size)
            }
            let pixels = size.pixels(scale: hiDPI ? 2 : 1)
            guard pixels.width <= Self.maxPixelDimension, pixels.height <= Self.maxPixelDimension else {
                throw .pixelSizeTooLarge(pixels)
            }
        }
        guard Self.supportedRefreshRates.contains(refreshRate) else { throw .refreshRateOutOfRange(refreshRate) }
        guard panel.nativePixels.width > 0, panel.nativePixels.height > 0,
              panel.physicalSize.widthMillimeters > 0, panel.physicalSize.heightMillimeters > 0
        else { throw .invalidPanel }
    }
}

public enum VirtualDisplayConfigurationError: Error, Hashable, Sendable, CustomStringConvertible {
    case emptyName
    case resolutionOutOfRange(PointSize)
    case pixelSizeTooLarge(PixelSize)
    case refreshRateOutOfRange(Double)
    case invalidPanel

    public var description: String {
        switch self {
        case .emptyName: "display name must not be empty"
        case .resolutionOutOfRange(let size): "resolution \(size) outside \(VirtualDisplayConfiguration.supportedPointRange)"
        case .pixelSizeTooLarge(let size): "backing size \(size) exceeds \(VirtualDisplayConfiguration.maxPixelDimension)px"
        case .refreshRateOutOfRange(let rate): "refresh rate \(rate)Hz outside \(VirtualDisplayConfiguration.supportedRefreshRates)"
        case .invalidPanel: "panel pixels and physical size must be positive"
        }
    }
}

extension VirtualDisplayConfiguration: Codable {
    enum CodingKeys: String, CodingKey {
        case profile, name, identity, panel, resolution, hiDPI, refreshRate, orientation, arrangement, extraResolutions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profile: DeviceProfile
        if let id = try container.decodeIfPresent(String.self, forKey: .profile) {
            guard let named = DeviceProfile.named(id) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .profile, in: container,
                    debugDescription: "unknown device profile '\(id)'; known: \(DeviceProfile.all.map(\.id).joined(separator: ", "))"
                )
            }
            profile = named
        } else {
            profile = .default
        }
        self = profile.configuration()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? name
        identity = try container.decodeIfPresent(DisplayIdentity.self, forKey: .identity) ?? identity
        panel = try container.decodeIfPresent(PanelSpecification.self, forKey: .panel) ?? panel
        resolution = try container.decodeIfPresent(PointSize.self, forKey: .resolution) ?? resolution
        hiDPI = try container.decodeIfPresent(Bool.self, forKey: .hiDPI) ?? hiDPI
        refreshRate = try container.decodeIfPresent(Double.self, forKey: .refreshRate) ?? refreshRate
        orientation = try container.decodeIfPresent(DisplayOrientation.self, forKey: .orientation) ?? orientation
        arrangement = try container.decodeIfPresent(DisplayArrangement.self, forKey: .arrangement) ?? arrangement
        extraResolutions = try container.decodeIfPresent([PointSize].self, forKey: .extraResolutions) ?? extraResolutions
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(profileID, forKey: .profile)
        try container.encode(name, forKey: .name)
        try container.encode(identity, forKey: .identity)
        try container.encode(panel, forKey: .panel)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(hiDPI, forKey: .hiDPI)
        try container.encode(refreshRate, forKey: .refreshRate)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(arrangement, forKey: .arrangement)
        try container.encode(extraResolutions, forKey: .extraResolutions)
    }
}
