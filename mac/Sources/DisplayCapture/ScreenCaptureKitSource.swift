import CoreGraphics
import CoreMedia
import Foundation
import os
@preconcurrency import ScreenCaptureKit
import GingaCore

public enum CaptureError: Error, Hashable, Sendable, CustomStringConvertible {
    case permissionDenied
    case displayNotFound(CGDirectDisplayID)
    case invalidConfiguration(String)
    case alreadyRunning
    /// A `stop()` (or a newer start) superseded this start while it was waiting.
    case cancelled
    case streamFailed(String)
    /// The stream ended on its own, e.g. -3808 when the display sleeps or the screen locks.
    case streamStopped(code: Int, message: String)

    public var description: String {
        switch self {
        case .permissionDenied: "Screen Recording permission is not granted"
        case .displayNotFound(let id): "display \(id) is not available to ScreenCaptureKit"
        case .invalidConfiguration(let reason): "invalid capture configuration: \(reason)"
        case .alreadyRunning: "capture is already running"
        case .cancelled: "capture start was cancelled"
        case .streamFailed(let reason): "capture stream failed: \(reason)"
        case .streamStopped(let code, let message): "capture stream stopped (\(code)): \(message)"
        }
    }
}

/// Layer 2 — captures one display, identified only by its `CGDirectDisplayID`.
/// Knows nothing about how the display was created.
public protocol DisplayCaptureSource: AnyObject, Sendable {
    /// Starts delivering new frames to `onFrame` on a private high-priority queue.
    /// `onStop` is called if the stream ends without `stop()` being called.
    func start(
        displayID: CGDirectDisplayID,
        configuration: CaptureConfiguration,
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        onStop: @escaping @Sendable (CaptureError) -> Void
    ) async throws(CaptureError)

    func stop() async

    var statistics: CaptureStatisticsSnapshot { get }
}

/// ScreenCaptureKit implementation. Frames arrive only when content changes (idle screens cost
/// nearly nothing) and are IOSurface-backed, so they can go straight into VideoToolbox.
public actor ScreenCaptureKitSource: DisplayCaptureSource {
    public nonisolated let recorder = CaptureStatisticsRecorder()
    private let displayDiscoveryTimeout: Duration
    private let sampleQueue = DispatchQueue(label: "dev.ginga.capture.frames", qos: .userInteractive)
    private var stream: SCStream?
    /// Bumped by every start and stop, so a start suspended at an await knows it was superseded.
    private var generation: UInt64 = 0
    private var output: StreamOutput?

    /// - Parameter displayDiscoveryTimeout: new (virtual) displays can take seconds to show up
    ///   in `SCShareableContent`.
    public init(displayDiscoveryTimeout: Duration = .seconds(15)) {
        self.displayDiscoveryTimeout = displayDiscoveryTimeout
    }

    public nonisolated var statistics: CaptureStatisticsSnapshot { recorder.snapshot() }

    public func start(
        displayID: CGDirectDisplayID,
        configuration: CaptureConfiguration,
        onFrame: @escaping @Sendable (CapturedFrame) -> Void,
        onStop: @escaping @Sendable (CaptureError) -> Void
    ) async throws(CaptureError) {
        guard stream == nil else { throw .alreadyRunning }
        do {
            try configuration.validate()
        } catch {
            throw .invalidConfiguration(error.description)
        }
        guard ScreenCapturePermission.isGranted else { throw .permissionDenied }
        // The actor is re-entrant at every await: a stop() or another start() may run meanwhile.
        // Each of them bumps the generation; a start that finds it changed undoes itself.
        generation &+= 1
        let token = generation

        let display = try await findDisplay(displayID)
        guard token == generation else { throw .cancelled }
        let displayPixels = DisplayGeometry.pixelSize(of: displayID) ?? PixelSize(width: display.width, height: display.height)
        let outputSize = CaptureSizing.outputSize(displayPixels: displayPixels, maxOutputSize: configuration.maxOutputSize)
        let streamConfiguration = configuration.streamConfiguration(outputSize: outputSize)
        let filter = SCContentFilter(display: display, excludingWindows: [])

        let output = StreamOutput(recorder: recorder, onFrame: onFrame) { [weak self] ended, error in
            onStop(error)
            Task { await self?.streamEnded(ended) }
        }
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()
        } catch {
            output.invalidate()
            Log.capture.error("capture.start-failed display=\(displayID) reason=\(String(describing: error), privacy: .public)")
            throw .streamFailed(String(describing: error))
        }
        guard token == generation, self.stream == nil else {
            // Superseded while starting: never leave a stream running that nothing records.
            output.invalidate()
            try? await stream.stopCapture()
            throw .cancelled
        }
        recorder.reset()
        self.stream = stream
        self.output = output
        Log.capture.info("capture.started display=\(displayID) displayPixels=\(displayPixels.description, privacy: .public) output=\(outputSize.description, privacy: .public) format=\(configuration.pixelFormat.rawValue, privacy: .public) interval=\(configuration.minimumFrameInterval.seconds)s queueDepth=\(configuration.queueDepth)")
    }

    public func stop() async {
        generation &+= 1  // cancels a start that is still waiting
        guard let stream else { return }
        self.stream = nil
        output?.invalidate()
        output = nil
        do {
            try await stream.stopCapture()
        } catch {
            Log.capture.debug("capture.stop-ignored reason=\(String(describing: error), privacy: .public)")
        }
        Log.capture.info("capture.stopped")
    }

    /// The stream stopped on its own. Only forget it if it is still the current one: a late
    /// callback from an older stream must not orphan the stream that replaced it.
    private func streamEnded(_ ended: StreamOutput) {
        guard ended === output else { return }
        stream = nil
        output = nil
    }

    private func findDisplay(_ displayID: CGDirectDisplayID) async throws(CaptureError) -> SCDisplay {
        let deadline = MediaTime.now().advanced(by: displayDiscoveryTimeout)
        var attempts = 0
        while true {
            attempts += 1
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let display = content.displays.first(where: { $0.displayID == displayID }) {
                    if attempts > 1 { Log.capture.info("capture.display-found display=\(displayID) attempts=\(attempts)") }
                    return display
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == SCStreamErrorDomain, nsError.code == SCStreamError.Code.userDeclined.rawValue {
                    throw .permissionDenied
                }
                Log.capture.debug("capture.shareable-content-failed reason=\(String(describing: error), privacy: .public)")
            }
            guard MediaTime.now() < deadline else { throw .displayNotFound(displayID) }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                throw .cancelled  // don't spin on window enumeration once nobody wants this start
            }
        }
    }
}

/// Receives ScreenCaptureKit callbacks on the sample queue.
///
/// `@unchecked Sendable`: all stored properties are immutable except `state`, which is guarded
/// by an unfair lock.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let recorder: CaptureStatisticsRecorder
    private let onFrame: @Sendable (CapturedFrame) -> Void
    private let onUnexpectedStop: @Sendable (StreamOutput, CaptureError) -> Void
    private let timebase = HostTimebase.current
    private let state = OSAllocatedUnfairLock(initialState: (sequence: UInt64(0), active: true))

    init(recorder: CaptureStatisticsRecorder, onFrame: @escaping @Sendable (CapturedFrame) -> Void, onUnexpectedStop: @escaping @Sendable (StreamOutput, CaptureError) -> Void) {
        self.recorder = recorder
        self.onFrame = onFrame
        self.onUnexpectedStop = onUnexpectedStop
    }

    func invalidate() {
        state.withLock { $0.active = false }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        let arrival = MediaTime.now()
        let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first ?? [:]
        let metadata = FrameMetadata(attachments: attachments, timebase: timebase)
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let pixelSize = pixelBuffer.map { PixelSize(width: CVPixelBufferGetWidth($0), height: CVPixelBufferGetHeight($0)) }
        recorder.record(metadata, arrival: arrival, pixelSize: pixelSize)

        guard metadata.status == .complete, let pixelBuffer, let pixelSize, let displayTime = metadata.displayTime else { return }
        let sequence: UInt64? = state.withLock { state in
            guard state.active else { return nil }
            state.sequence += 1
            return state.sequence
        }
        guard let sequence else { return }
        onFrame(CapturedFrame(
            sequenceNumber: sequence,
            pixelBuffer: pixelBuffer,
            sampleBuffer: sampleBuffer,
            pixelSize: pixelSize,
            displayTime: displayTime,
            arrivalTime: arrival,
            dirtyRectCount: metadata.dirtyRectCount,
            scaleFactor: metadata.scaleFactor
        ))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let wasActive = state.withLock { state in
            defer { state.active = false }
            return state.active
        }
        guard wasActive else { return }
        let nsError = error as NSError
        Log.capture.error("capture.stream-stopped code=\(nsError.code) reason=\(nsError.localizedDescription, privacy: .public)")
        onUnexpectedStop(self, .streamStopped(code: nsError.code, message: nsError.localizedDescription))
    }
}
