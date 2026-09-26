import CoreGraphics
import CoreVideo
import Foundation
import Tab2MacCore
import Testing
@testable import DisplayCapture

/// Captures the main display for a moment. Needs Screen Recording permission for the process
/// running the tests, so it only runs when explicitly enabled *and* permission is present.
@Suite(
    "ScreenCaptureIntegration",
    .enabled(if: ProcessInfo.processInfo.environment["T2M_INTEGRATION"] == "1" && ScreenCapturePermission.isGranted)
)
struct ScreenCaptureIntegrationTests {
    @Test func deliversEncoderReadyFramesFromADisplay() async throws {
        let source = ScreenCaptureKitSource()
        let received = FrameCounter()
        try await source.start(
            displayID: CGMainDisplayID(),
            configuration: CaptureConfiguration(frameRate: 60),
            onFrame: { frame in received.add(frame) },
            onStop: { _ in }
        )
        try await Task.sleep(for: .seconds(1))
        await source.stop()
        // A static screen produces few "complete" frames; at least the first one always arrives.
        #expect(received.count >= 1)
        #expect(received.lastFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }
}

final class FrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    private var _lastFormat: OSType = 0

    func add(_ frame: CapturedFrame) {
        lock.withLock {
            _count += 1
            _lastFormat = CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
        }
    }

    var count: Int { lock.withLock { _count } }
    var lastFormat: OSType { lock.withLock { _lastFormat } }
}
