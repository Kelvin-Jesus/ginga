import Foundation

/// A size in device pixels (framebuffer / video frame dimensions).
public struct PixelSize: Hashable, Sendable, Codable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var swapped: PixelSize { PixelSize(width: height, height: width) }
    public var isPortrait: Bool { height > width }
    public var isLandscape: Bool { width >= height }
    /// Largest size with the same aspect ratio that fits inside `bounds`. Never upscales.
    public func aspectFit(within bounds: PixelSize) -> PixelSize {
        guard width > bounds.width || height > bounds.height else { return self }
        let scale = min(Double(bounds.width) / Double(width), Double(bounds.height) / Double(height))
        return PixelSize(
            width: min(bounds.width, Int((Double(width) * scale).rounded())),
            height: min(bounds.height, Int((Double(height) * scale).rounded()))
        )
    }

    /// 4:2:0 chroma subsampling (NV12, H.264/HEVC) requires even dimensions.
    public var roundedDownToEven: PixelSize {
        PixelSize(width: width & ~1, height: height & ~1)
    }

    public var description: String { "\(width)×\(height)px" }
}

/// A size in logical points ("looks like" resolution in macOS terms).
public struct PointSize: Hashable, Sendable, Codable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var swapped: PointSize { PointSize(width: height, height: width) }
    public var isPortrait: Bool { height > width }
    public var isLandscape: Bool { width >= height }

    public func pixels(scale: Int) -> PixelSize {
        PixelSize(width: width * scale, height: height * scale)
    }

    public var description: String { "\(width)×\(height)pt" }
}

/// A physical panel size in millimetres.
public struct PhysicalSize: Hashable, Sendable, Codable {
    public var widthMillimeters: Double
    public var heightMillimeters: Double

    public init(widthMillimeters: Double, heightMillimeters: Double) {
        self.widthMillimeters = widthMillimeters
        self.heightMillimeters = heightMillimeters
    }

    /// Derives width/height from a diagonal and the aspect ratio of the native pixel grid.
    public init(diagonalInches: Double, aspectOf pixels: PixelSize) {
        let diagonalMillimeters = diagonalInches * 25.4
        let diagonalPixels = (Double(pixels.width * pixels.width + pixels.height * pixels.height)).squareRoot()
        self.init(
            widthMillimeters: diagonalMillimeters * Double(pixels.width) / diagonalPixels,
            heightMillimeters: diagonalMillimeters * Double(pixels.height) / diagonalPixels
        )
    }

    public var swapped: PhysicalSize {
        PhysicalSize(widthMillimeters: heightMillimeters, heightMillimeters: widthMillimeters)
    }

    public func pixelsPerInch(for pixels: PixelSize) -> Double {
        Double(pixels.width) / (widthMillimeters / 25.4)
    }
}
