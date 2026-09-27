import GingaCore

/// Known receiving devices. A profile supplies panel facts and sensible resolution choices;
/// every field can still be overridden in `VirtualDisplayConfiguration`.
public struct DeviceProfile: Hashable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let panel: PanelSpecification
    /// "Looks like" resolutions offered for this panel (landscape, used with HiDPI).
    public let resolutionOptions: [PointSize]
    public let defaultResolution: PointSize
    public let refreshRates: [Double]
    public let productID: UInt32
    /// Model-number prefixes (Android `Build.MODEL`, e.g. "SM-X730") that identify the device.
    public let models: [String]

    public init(
        id: String,
        displayName: String,
        panel: PanelSpecification,
        resolutionOptions: [PointSize],
        defaultResolution: PointSize,
        refreshRates: [Double],
        productID: UInt32,
        models: [String] = []
    ) {
        self.models = models
        self.id = id
        self.displayName = displayName
        self.panel = panel
        self.resolutionOptions = resolutionOptions
        self.defaultResolution = defaultResolution
        self.refreshRates = refreshRates
        self.productID = productID
    }

    /// Samsung Galaxy Tab S11 (2025): 11", 2560×1600, up to 120 Hz.
    public static let galaxyTabS11 = DeviceProfile(
        id: "galaxy-tab-s11",
        displayName: "Galaxy Tab S11",
        panel: PanelSpecification(
            nativePixels: PixelSize(width: 2560, height: 1600),
            physicalSize: PhysicalSize(diagonalInches: 11.0, aspectOf: PixelSize(width: 2560, height: 1600)),
            maxRefreshRate: 120
        ),
        resolutionOptions: [
            PointSize(width: 1024, height: 640),
            PointSize(width: 1280, height: 800),  // pixel-exact Retina
            PointSize(width: 1440, height: 900),
            PointSize(width: 1600, height: 1000),
        ],
        defaultResolution: PointSize(width: 1280, height: 800),
        refreshRates: [60, 120],
        productID: 0x5311,
        models: ["SM-X730", "SM-X736", "SM-X738"]
    )

    /// Samsung Galaxy Tab S11 Ultra (2025): 14.6", 2960×1848, up to 120 Hz.
    public static let galaxyTabS11Ultra = DeviceProfile(
        id: "galaxy-tab-s11-ultra",
        displayName: "Galaxy Tab S11 Ultra",
        panel: PanelSpecification(
            nativePixels: PixelSize(width: 2960, height: 1848),
            physicalSize: PhysicalSize(diagonalInches: 14.6, aspectOf: PixelSize(width: 2960, height: 1848)),
            maxRefreshRate: 120
        ),
        resolutionOptions: [
            PointSize(width: 1280, height: 800),
            PointSize(width: 1480, height: 924),  // pixel-exact Retina
            PointSize(width: 1600, height: 1000),
            PointSize(width: 1920, height: 1200),
        ],
        defaultResolution: PointSize(width: 1480, height: 924),
        refreshRates: [60, 120],
        productID: 0x5312,
        models: ["SM-X930", "SM-X936", "SM-X938"]
    )

    /// Samsung Galaxy Tab S9 FE+ (2023): 12.4" LCD, 2560×1600, up to 90 Hz.
    public static let galaxyTabS9FEPlus = DeviceProfile(
        id: "galaxy-tab-s9-fe-plus",
        displayName: "Galaxy Tab S9 FE+",
        panel: PanelSpecification(
            nativePixels: PixelSize(width: 2560, height: 1600),
            physicalSize: PhysicalSize(diagonalInches: 12.4, aspectOf: PixelSize(width: 2560, height: 1600)),
            maxRefreshRate: 90
        ),
        resolutionOptions: [
            PointSize(width: 1280, height: 800),  // pixel-exact Retina
            PointSize(width: 1440, height: 900),
            PointSize(width: 1600, height: 1000),
        ],
        defaultResolution: PointSize(width: 1280, height: 800),
        refreshRates: [60, 90],
        productID: 0x5391,
        models: ["SM-X610", "SM-X616", "SM-X618"]
    )

    /// Samsung Galaxy S25 Ultra (2025): 6.9" phone, 3120×1440, up to 120 Hz. Used in landscape;
    /// the default favours legibility over space on a small screen.
    public static let galaxyS25Ultra = DeviceProfile(
        id: "galaxy-s25-ultra",
        displayName: "Galaxy S25 Ultra",
        panel: PanelSpecification(
            nativePixels: PixelSize(width: 3120, height: 1440),
            physicalSize: PhysicalSize(diagonalInches: 6.9, aspectOf: PixelSize(width: 3120, height: 1440)),
            maxRefreshRate: 120
        ),
        resolutionOptions: [
            PointSize(width: 1040, height: 480),
            PointSize(width: 1248, height: 576),
            PointSize(width: 1560, height: 720),  // pixel-exact Retina
        ],
        defaultResolution: PointSize(width: 1248, height: 576),
        refreshRates: [60, 120],
        productID: 0x5325,
        models: ["SM-S938"]
    )

    /// Any 16:10, 1920×1200 tablet (useful for testing with other hardware).
    public static let generic1920x1200 = DeviceProfile(
        id: "generic-1920x1200",
        displayName: "Tablet Display",
        panel: PanelSpecification(
            nativePixels: PixelSize(width: 1920, height: 1200),
            physicalSize: PhysicalSize(diagonalInches: 10.1, aspectOf: PixelSize(width: 1920, height: 1200)),
            maxRefreshRate: 60
        ),
        resolutionOptions: [
            PointSize(width: 960, height: 600),  // pixel-exact Retina
            PointSize(width: 1280, height: 800),
            PointSize(width: 1440, height: 900),
        ],
        defaultResolution: PointSize(width: 960, height: 600),
        refreshRates: [60],
        productID: 0x5300
    )

    public static let all: [DeviceProfile] = [.galaxyTabS11, .galaxyTabS11Ultra, .galaxyTabS9FEPlus, .galaxyS25Ultra, .generic1920x1200]

    /// The profile for a model number, if Ginga knows the device.
    public static func matching(model: String) -> DeviceProfile? {
        all.first { profile in profile.models.contains { model.uppercased().hasPrefix($0) } }
    }

    /// A profile for any other Android device, from what it reports in HELLO: its panel in
    /// landscape, pixel-exact Retina by default, and its fastest refresh rate as the maximum.
    public static func generic(model: String, widthPx: Int, heightPx: Int, densityDpi: Int, refreshRates: [Double]) -> DeviceProfile {
        let pixels = PixelSize(width: max(widthPx, heightPx), height: min(widthPx, heightPx))
        let inches = densityDpi > 0 ? (Double(pixels.width * pixels.width + pixels.height * pixels.height)).squareRoot() / Double(densityDpi) : 11
        let exact = PointSize(width: pixels.width / 2, height: pixels.height / 2)
        func scaled(_ factor: Double) -> PointSize {
            PointSize(width: Int(Double(exact.width) * factor) / 8 * 8, height: Int(Double(exact.height) * factor) / 8 * 8)
        }
        let maxRate = min(refreshRates.max() ?? 60, 120)
        return DeviceProfile(
            id: "auto",
            displayName: model,
            panel: PanelSpecification(nativePixels: pixels, physicalSize: PhysicalSize(diagonalInches: inches, aspectOf: pixels), maxRefreshRate: maxRate),
            resolutionOptions: [scaled(0.8), exact, scaled(1.25)],
            defaultResolution: exact,
            refreshRates: [60, maxRate].filter { $0 <= maxRate }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } },
            productID: 0x5300
        )
    }
    public static let `default` = galaxyTabS11

    public static func named(_ id: String) -> DeviceProfile? {
        all.first { $0.id == id }
    }

    /// Defaults to 60 Hz when the panel supports it: WindowServer composes the virtual display (and
    /// apps on it render) at its refresh rate: streaming an animated window costs +229 mW at 60 Hz
    /// and about 0.8 W more at 120 Hz (`ginga bench-power`). 120 Hz is an opt-in.
    public func configuration(
        resolution: PointSize? = nil,
        orientation: DisplayOrientation = .landscape,
        refreshRate: Double? = nil,
        hiDPI: Bool = true
    ) -> VirtualDisplayConfiguration {
        VirtualDisplayConfiguration(
            profileID: id,
            name: displayName,
            identity: DisplayIdentity(vendorID: DisplayIdentity.gingaVendorID, productID: productID, serialNumber: 1),
            panel: panel,
            resolution: resolution ?? defaultResolution,
            hiDPI: hiDPI,
            refreshRate: refreshRate ?? (refreshRates.contains(60) ? 60 : refreshRates.max() ?? 60),
            orientation: orientation,
            arrangement: .automatic,
            extraResolutions: resolutionOptions
        )
    }
}
