import AppKit
import AVFoundation
import CoreMedia
import DisplayCapture
import os
import SwiftUI
import GingaSession

/// Renders captured frames without copying: the IOSurface-backed sample buffers go straight
/// into an `AVSampleBufferDisplayLayer` (the Mac-side stand-in for the Android SurfaceView).
final class PreviewRenderer: @unchecked Sendable {
    // AVSampleBufferVideoRenderer is internally synchronized and may be fed from any thread.
    private struct State {
        var format: CMVideoFormatDescription?
    }

    private let renderer: AVSampleBufferVideoRenderer
    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    init(layer: AVSampleBufferDisplayLayer) {
        renderer = layer.sampleBufferRenderer
    }

    /// Called on the capture queue. Never blocks: frames are dropped if the layer is busy.
    func enqueue(_ frame: CapturedFrame) {
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData, let sample = makeSampleBuffer(for: frame.pixelBuffer) else { return }
        renderer.enqueue(sample)
    }

    func flush() {
        renderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }

    /// Wraps the pixel buffer in a fresh sample buffer marked "display immediately", leaving the
    /// capture layer's sample buffer untouched for other consumers.
    private func makeSampleBuffer(for pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        // Unchecked: the closure runs synchronously on this thread; nothing escapes.
        let format: CMVideoFormatDescription? = state.withLockUnchecked { state in
            if let existing = state.format, CMVideoFormatDescriptionMatchesImageBuffer(existing, imageBuffer: pixelBuffer) {
                return existing
            }
            var created: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &created)
            state.format = created
            return created
        }
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample
        else { return nil }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}

final class PreviewView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.frame = bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(displayLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

struct StatsOverlay: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.overlayLines, id: \.self) { Text($0) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
        .fixedSize()
    }
}

/// Debug window on the Mac showing exactly what capture produces from the virtual display.
@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private let previewView = PreviewView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    private lazy var renderer = PreviewRenderer(layer: previewView.displayLayer)
    private var sinkToken: FrameSinkRegistry.Token?
    private var overlay: NSHostingView<StatsOverlay>?
    private var isShown = false

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = tr("Ginga — prévia de debug (quadros capturados do display virtual)", "Ginga — debug preview (frames captured from the virtual display)")
        window.contentAspectRatio = NSSize(width: 16, height: 10)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let container = NSView(frame: window.contentLayoutRect)
        previewView.frame = container.bounds
        previewView.autoresizingMask = [.width, .height]
        container.addSubview(previewView)
        window.contentView = container
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        guard let window else { return }
        updateOverlay()
        if !window.isVisible, let home = NSScreen.screens.first(where: { isBuiltIn($0) }) ?? NSScreen.main {
            // Keep the preview off the virtual display to avoid capturing ourselves recursively.
            window.setFrameOrigin(NSPoint(x: home.visibleFrame.minX + 40, y: home.visibleFrame.minY + 40))
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        setShown(true)
    }

    func windowWillClose(_ notification: Notification) {
        setShown(false)
    }

    /// Covered, minimized or on another Space: without a tablet, nothing needs frames then.
    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        setShown(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
    }

    /// Frames are captured, drawn and the overlay refreshed only while the preview can be seen.
    private func setShown(_ shown: Bool) {
        guard shown != isShown else { return }
        isShown = shown
        if shown { attach() } else { detach() }
        model.setObserving(self, visible: shown)
        model.setPreviewCapture(shown)
    }

    private func attach() {
        guard sinkToken == nil else { return }
        let renderer = renderer
        sinkToken = model.session.frames.add { frame in renderer.enqueue(frame) }
    }

    private func detach() {
        if let sinkToken { model.session.frames.remove(sinkToken) }
        sinkToken = nil
        renderer.flush()
    }

    private func updateOverlay() {
        guard model.applied.diagnostics.overlayEnabled, overlay == nil, let container = window?.contentView else { return }
        let hosting = NSHostingView(rootView: StatsOverlay(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        overlay = hosting
    }

    private func isBuiltIn(_ screen: NSScreen) -> Bool {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CGDisplayIsBuiltin(id) != 0
    }
}
