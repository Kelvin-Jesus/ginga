import Foundation
import Testing
@testable import Tab2MacSession

@MainActor
@Suite("CursorTracker")
struct CursorTrackerTests {
    /// The pointer image is rendered at the stream's scale, as a PNG, with a stable nonzero id.
    @Test func theShapeIsAPNGAtTheStreamScale() throws {
        let shape = try #require(CursorTracker.currentShape(scale: 2), "no pointer image in this environment")
        let again = try #require(CursorTracker.currentShape(scale: 2))
        #expect(shape.png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(shape.width >= 16 && shape.height >= 16)
        #expect((0...shape.width).contains(shape.hotspotX) && (0...shape.height).contains(shape.hotspotY))
        #expect(shape.id != 0 && shape.id == again.id)
        let single = try #require(CursorTracker.currentShape(scale: 1))
        #expect(single.width * 2 == shape.width || abs(single.width * 2 - shape.width) <= 1)
    }
}
