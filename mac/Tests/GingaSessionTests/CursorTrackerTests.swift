import Foundation
import Testing
@testable import GingaSession

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

@MainActor
@Suite("CursorTracker settling")
struct CursorTrackerSettlingTests {
    static func shape(_ id: UInt32) -> CursorTracker.Shape {
        CursorTracker.Shape(id: id, width: 32, height: 32, hotspotX: 0, hotspotY: 0, png: Data([UInt8(id)]))
    }

    /// A tap jumps the pointer onto the tablet while the image is still the I-beam of the window
    /// it left; the app under it sets the arrow a moment later. The arrow must follow without
    /// another move.
    @Test func theImageIsReadAgainAfterThePointerStops() async throws {
        var system = Self.shape(3)  // I-beam when the move is seen
        var samples: [CursorTracker.Sample] = []
        let tracker = CursorTracker(scale: 2, readShape: { _ in system }) { samples.append($0) }
        tracker.report(CGPoint(x: -600, y: 400))
        #expect(samples.map(\.shape?.id) == [3])
        system = Self.shape(5)  // the arrow, once the app under the pointer set it
        #expect(await eventually { samples.map(\.shape?.id) == [3, 5] })
        #expect(samples.last?.location == CGPoint(x: -600, y: 400))
        withExtendedLifetime(tracker) {}  // the checks hold it weakly, as the host holds it in the app
    }

    /// Nothing is sent again when the image didn't change, and nothing after stop.
    @Test func noRepeatsAndNothingAfterStop() async throws {
        var system = Self.shape(3)
        var samples: [CursorTracker.Sample] = []
        let tracker = CursorTracker(scale: 2, readShape: { _ in system }) { samples.append($0) }
        tracker.report(CGPoint(x: 1, y: 1))
        try await Task.sleep(for: .milliseconds(500))
        #expect(samples.count == 1)
        tracker.report(CGPoint(x: 2, y: 2))
        tracker.stop()
        system = Self.shape(9)
        try await Task.sleep(for: .milliseconds(500))
        #expect(samples.count == 2)
    }

    /// Lazy apps: the image changes only after the first look; the later look catches it.
    @Test func aLaterLookCatchesLazyApps() async throws {
        // The app sets its image only after the move and the first look have read the old one, so
        // only the later look can see it. Counting reads (not timing a change) keeps a slow CI
        // runner from changing the image after the later look already happened.
        var reads = 0
        var samples: [CursorTracker.Sample] = []
        let tracker = CursorTracker(scale: 2, readShape: { _ in reads += 1; return Self.shape(reads <= 2 ? 3 : 7) }) { samples.append($0) }
        tracker.report(CGPoint(x: 1, y: 1))
        #expect(await eventually(timeout: .seconds(5)) { samples.map(\.shape?.id) == [3, 7] })
        #expect(reads == 3)  // the move, the first look (still 3), the later look (7)
        withExtendedLifetime(tracker) {}
    }
}
