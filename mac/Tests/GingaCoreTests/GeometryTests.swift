import Foundation
import Testing
@testable import GingaCore

@Suite("Geometry")
struct GeometryTests {
    @Test func pointSizeSwapsForPortrait() {
        let landscape = PointSize(width: 1280, height: 800)
        #expect(landscape.swapped == PointSize(width: 800, height: 1280))
        #expect(landscape.isLandscape)
        #expect(landscape.swapped.isPortrait)
    }

    @Test func pointSizeScalesToPixels() {
        #expect(PointSize(width: 1280, height: 800).pixels(scale: 2) == PixelSize(width: 2560, height: 1600))
        #expect(PointSize(width: 1280, height: 800).pixels(scale: 1) == PixelSize(width: 1280, height: 800))
    }

    @Test func aspectFitDownscalesToBounds() {
        let bounds = PixelSize(width: 2560, height: 1600)
        #expect(PixelSize(width: 2880, height: 1800).aspectFit(within: bounds) == bounds)
        #expect(PixelSize(width: 3840, height: 2400).aspectFit(within: bounds) == bounds)
    }

    @Test func aspectFitNeverUpscales() {
        let bounds = PixelSize(width: 2560, height: 1600)
        #expect(PixelSize(width: 2048, height: 1280).aspectFit(within: bounds) == PixelSize(width: 2048, height: 1280))
    }

    @Test func aspectFitPreservesPortraitAspect() {
        let fitted = PixelSize(width: 1600, height: 2560).aspectFit(within: PixelSize(width: 2560, height: 1600))
        #expect(fitted == PixelSize(width: 1000, height: 1600))
    }

    @Test func roundsDownToEvenForChromaSubsampling() {
        #expect(PixelSize(width: 1001, height: 1601).roundedDownToEven == PixelSize(width: 1000, height: 1600))
        #expect(PixelSize(width: 1000, height: 1600).roundedDownToEven == PixelSize(width: 1000, height: 1600))
    }

    @Test func physicalSizeFromDiagonalMatchesGalaxyTabS11Panel() {
        let size = PhysicalSize(diagonalInches: 11.0, aspectOf: PixelSize(width: 2560, height: 1600))
        #expect(abs(size.widthMillimeters - 236.9) < 0.1)
        #expect(abs(size.heightMillimeters - 148.1) < 0.1)
        #expect(size.swapped.widthMillimeters == size.heightMillimeters)
    }

    @Test func pixelDensityIsDerivedFromPhysicalSize() {
        let size = PhysicalSize(diagonalInches: 11.0, aspectOf: PixelSize(width: 2560, height: 1600))
        let ppi = size.pixelsPerInch(for: PixelSize(width: 2560, height: 1600))
        #expect(abs(ppi - 274.4) < 0.5)
    }

    @Test func geometryIsCodableAsPlainObjects() throws {
        let json = try JSONEncoder.sortedKeys.encode(PointSize(width: 1280, height: 800))
        #expect(String(decoding: json, as: UTF8.self) == #"{"height":800,"width":1280}"#)
    }
}

extension JSONEncoder {
    static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
