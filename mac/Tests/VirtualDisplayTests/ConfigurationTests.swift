import Foundation
import Testing
import GingaCore
@testable import VirtualDisplay

@Suite("DeviceProfile")
struct DeviceProfileTests {
    @Test func galaxyTabS11MatchesThePanel() {
        let profile = DeviceProfile.galaxyTabS11
        #expect(profile.panel.nativePixels == PixelSize(width: 2560, height: 1600))
        #expect(abs(profile.panel.physicalSize.widthMillimeters - 236.9) < 0.1)
        #expect(profile.panel.maxRefreshRate == 120)
        #expect(profile.defaultResolution.pixels(scale: 2) == profile.panel.nativePixels)
    }

    @Test func ultraDefaultIsPixelExactRetina() {
        let profile = DeviceProfile.galaxyTabS11Ultra
        #expect(profile.defaultResolution.pixels(scale: 2) == profile.panel.nativePixels)
    }

    @Test func everyProfileOffersItsDefaultAndValidates() throws {
        for profile in DeviceProfile.all {
            #expect(profile.resolutionOptions.contains(profile.defaultResolution), "\(profile.id)")
            try profile.configuration().validate()
        }
    }

    @Test func profilesAreLookedUpByID() {
        #expect(DeviceProfile.named("galaxy-tab-s11") == .galaxyTabS11)
        #expect(DeviceProfile.named("nope") == nil)
    }
}

@Suite("VirtualDisplayConfiguration")
struct VirtualDisplayConfigurationTests {
    @Test func decodesAProfileWithSparseOverrides() throws {
        let json = #"""
        { "profile": "galaxy-tab-s11", "resolution": { "width": 1440, "height": 900 },
          "refreshRate": 120, "orientation": "portrait",
          "arrangement": { "placement": "left", "alignment": "center" } }
        """#
        let configuration = try JSONDecoder().decode(VirtualDisplayConfiguration.self, from: Data(json.utf8))
        #expect(configuration.profileID == "galaxy-tab-s11")
        #expect(configuration.resolution == PointSize(width: 1440, height: 900))
        #expect(configuration.refreshRate == 120)
        #expect(configuration.orientation == .portrait)
        #expect(configuration.arrangement == DisplayArrangement(placement: .left, alignment: .center))
        // Everything else comes from the profile.
        #expect(configuration.panel == DeviceProfile.galaxyTabS11.panel)
        #expect(configuration.hiDPI)
        #expect(configuration.name == "Galaxy Tab S11")
    }

    @Test func emptyObjectDecodesToTheDefaultProfile() throws {
        let configuration = try JSONDecoder().decode(VirtualDisplayConfiguration.self, from: Data("{}".utf8))
        #expect(configuration == DeviceProfile.galaxyTabS11.configuration())
    }

    @Test func unknownProfileIsADecodingError() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(VirtualDisplayConfiguration.self, from: Data(#"{"profile":"nokia-3310"}"#.utf8))
        }
    }

    @Test func roundTripsThroughJSON() throws {
        var configuration = DeviceProfile.galaxyTabS11Ultra.configuration(orientation: .portrait, refreshRate: 120)
        configuration.arrangement = DisplayArrangement(placement: .above, alignment: .end)
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(VirtualDisplayConfiguration.self, from: data) == configuration)
    }

    @Test func validationRejectsNonsense() {
        var configuration = DeviceProfile.galaxyTabS11.configuration()
        configuration.refreshRate = 0
        #expect(throws: VirtualDisplayConfigurationError.refreshRateOutOfRange(0)) { try configuration.validate() }

        configuration = DeviceProfile.galaxyTabS11.configuration()
        configuration.resolution = PointSize(width: 100, height: 80)
        #expect(throws: VirtualDisplayConfigurationError.resolutionOutOfRange(PointSize(width: 100, height: 80))) { try configuration.validate() }

        configuration = DeviceProfile.galaxyTabS11.configuration()
        configuration.resolution = PointSize(width: 5000, height: 3000)
        #expect(throws: VirtualDisplayConfigurationError.pixelSizeTooLarge(PixelSize(width: 10000, height: 6000))) { try configuration.validate() }

        configuration = DeviceProfile.galaxyTabS11.configuration()
        configuration.name = "  "
        #expect(throws: VirtualDisplayConfigurationError.emptyName) { try configuration.validate() }
    }
}
