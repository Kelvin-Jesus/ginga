// swift-tools-version: 6.0
//
// Tab2Mac — macOS side.
//
// Module layering (arrows = "depends on"); see docs/architecture.md.
//
//   Tab2MacApp / t2m  (composition roots: the only place that picks a VirtualDisplayBackend)
//        │
//        ├── Tab2MacSession ──► VirtualDisplay, DisplayCapture, Tab2MacCore
//        ├── CGVirtualDisplayBackend ──► VirtualDisplay, CGVirtualDisplayShim (Obj-C, private API)
//        │
//   VirtualDisplay   (Layer 1: abstraction + public CoreGraphics display APIs; no capture/UI/network)
//   DisplayCapture   (Layer 2: ScreenCaptureKit; consumes a CGDirectDisplayID only)
//   Tab2MacCore      (clock, geometry, logging, statistics, process metrics)
import PackageDescription

let package = Package(
    name: "Tab2Mac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tab2Mac", targets: ["Tab2MacApp"]),
        .executable(name: "t2m", targets: ["t2m"]),
    ],
    targets: [
        // Shared primitives. No dependency on any other module in this package.
        .target(name: "Tab2MacCore"),

        // Layer 1 — Virtual Display Provider: the abstraction everything else depends on.
        .target(name: "VirtualDisplay", dependencies: ["Tab2MacCore"]),

        // The ONLY code that knows about the private CGVirtualDisplay API (Objective-C so that
        // exceptions can be caught and selectors verified before use).
        .target(name: "CGVirtualDisplayShim", publicHeadersPath: "include"),

        // Path A backend: adapts the shim to `VirtualDisplayBackend`.
        .target(name: "CGVirtualDisplayBackend", dependencies: ["VirtualDisplay", "CGVirtualDisplayShim", "Tab2MacCore"]),

        // Layer 2 — Display Capture (ScreenCaptureKit). Knows nothing about how the display was made.
        .target(name: "DisplayCapture", dependencies: ["Tab2MacCore"]),

        // Layer 3 — Video Pipeline: VideoToolbox encode/decode, Annex-B, pacing. Independent of how
        // frames were produced (takes CVPixelBuffers + host timestamps).
        .target(name: "VideoPipeline", dependencies: ["Tab2MacCore"]),

        // Wire protocol v1 (protocol/PROTOCOL.md): framing, messages, clock sync, golden vectors.
        // Foundation only — no platform frameworks, so it stays a pure contract implementation.
        .target(name: "Tab2MacProtocol"),

        // Layer 4 — Transport: framed message connections (Network.framework TCP; AOA/Wi‑Fi later)
        // and the ADB bridge. Knows messages, not displays, capture or codecs.
        .target(name: "Transport", dependencies: ["Tab2MacProtocol", "Tab2MacCore"]),

        // Wiring of layers 1+2, configuration, self-test and benchmarks. Backend-agnostic.
        .target(name: "Tab2MacSession", dependencies: ["VirtualDisplay", "DisplayCapture", "VideoPipeline", "Tab2MacCore"]),

        // No-router mode (§6b): Bluetooth LE handover + joining the tablet's network (CoreWLAN).
        .target(name: "DirectLink", dependencies: ["Tab2MacSecurity", "Tab2MacCore"]),
        .testTarget(name: "DirectLinkTests", dependencies: ["DirectLink", "Tab2MacSecurity", "Tab2MacCore"]),

        // The composition shared by the app and `t2m run`.
        .target(
            name: "Tab2MacRuntime",
            dependencies: ["Tab2MacSession", "Tab2MacStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "DisplayCapture", "Transport", "USBAccessory", "Tab2MacSecurity", "DirectLink", "Tab2MacProtocol", "Tab2MacCore"]
        ),

        // Input forwarding (M5): gesture interpretation (pure) + CGEvent injection onto the virtual display.
        .target(name: "InputInjection", dependencies: ["Tab2MacProtocol", "Tab2MacCore"]),

        // Streaming: per-receiver sessions (handshake, encoder, backpressure, clock sync) over any
        // Transport, fed by a StreamHost (the virtual display, or a synthetic source for tests).
        .target(
            name: "Tab2MacStreaming",
            dependencies: ["Tab2MacSession", "VirtualDisplay", "DisplayCapture", "VideoPipeline", "Transport", "Tab2MacProtocol", "Tab2MacSecurity", "Tab2MacCore"]
        ),

        // M7 Wi‑Fi security: self-signed TLS identities, fingerprints, pairing codes, pins.
        .target(name: "Tab2MacSecurity", dependencies: ["Tab2MacCore"]),

        // M6 direct USB: Android Open Accessory. The Objective-C shim is the only code calling
        // IOUSBHost (no Swift overlay exists); the Swift module holds the protocol and policy.
        .target(name: "USBAccessoryShim", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit")]),
        .target(name: "USBAccessory", dependencies: ["USBAccessoryShim", "Transport", "Tab2MacProtocol", "Tab2MacCore"]),

        // Benchmarks only (linked by t2m, never by the app): SoC energy via IOReport (private,
        // resolved at runtime) and per-process CPU/energy/wake-ups via public libproc.
        .target(name: "EnergyMeter", dependencies: ["Tab2MacCore"]),

        // Composition roots.
        .executableTarget(
            name: "Tab2MacApp",
            dependencies: ["Tab2MacSession", "Tab2MacStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "DisplayCapture", "Transport", "USBAccessory", "Tab2MacSecurity", "DirectLink", "Tab2MacRuntime", "Tab2MacCore"]
        ),
        .executableTarget(
            name: "t2m",
            dependencies: [
                "Tab2MacSession", "Tab2MacStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "CGVirtualDisplayShim",
                "DisplayCapture", "VideoPipeline", "Transport", "Tab2MacCore", "Tab2MacProtocol", "EnergyMeter", "USBAccessory",
                "Tab2MacSecurity", "Tab2MacRuntime",
            ]
        ),

        // Test support: Objective-C fakes that mimic the private classes' exact selectors/type encodings.
        .target(name: "ShimFakes", path: "Tests/ShimFakes", publicHeadersPath: "include"),
        // Test support: simulated WindowServer / backend for the provider and session tests.
        .target(name: "VirtualDisplayTestSupport", dependencies: ["VirtualDisplay", "Tab2MacCore"], path: "Tests/VirtualDisplayTestSupport"),

        .testTarget(name: "Tab2MacCoreTests", dependencies: ["Tab2MacCore"]),
        .testTarget(name: "VirtualDisplayTests", dependencies: ["VirtualDisplay", "VirtualDisplayTestSupport", "Tab2MacCore"]),
        .testTarget(
            name: "CGVirtualDisplayBackendTests",
            dependencies: ["CGVirtualDisplayBackend", "CGVirtualDisplayShim", "ShimFakes", "VirtualDisplay", "Tab2MacCore"]
        ),
        .testTarget(name: "DisplayCaptureTests", dependencies: ["DisplayCapture", "Tab2MacCore"]),
        .testTarget(name: "Tab2MacProtocolTests", dependencies: ["Tab2MacProtocol"]),
        .testTarget(name: "VideoPipelineTests", dependencies: ["VideoPipeline", "Tab2MacCore"]),
        .testTarget(name: "TransportTests", dependencies: ["Transport", "Tab2MacProtocol", "Tab2MacSecurity", "Tab2MacCore"]),
        .testTarget(name: "InputInjectionTests", dependencies: ["InputInjection", "Tab2MacProtocol"]),
        .testTarget(name: "EnergyMeterTests", dependencies: ["EnergyMeter", "Tab2MacCore"]),
        .testTarget(name: "Tab2MacSecurityTests", dependencies: ["Tab2MacSecurity"]),
        .testTarget(name: "USBAccessoryTests", dependencies: ["USBAccessory", "USBAccessoryShim", "Transport", "Tab2MacProtocol"]),
        .testTarget(name: "Tab2MacAppTests", dependencies: ["Tab2MacApp"]),
        .testTarget(
            name: "Tab2MacStreamingTests",
            dependencies: [
                "Tab2MacStreaming", "Tab2MacSession", "VirtualDisplay", "VirtualDisplayTestSupport", "DisplayCapture",
                "VideoPipeline", "Transport", "Tab2MacProtocol", "Tab2MacSecurity", "Tab2MacCore",
            ]
        ),
        .testTarget(
            name: "Tab2MacSessionTests",
            dependencies: ["Tab2MacSession", "VirtualDisplay", "VirtualDisplayTestSupport", "DisplayCapture", "Tab2MacCore"]
        ),
    ]
)
