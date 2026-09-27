// swift-tools-version: 6.0
//
// Ginga — macOS side.
//
// Module layering (arrows = "depends on"); see docs/architecture.md.
//
//   GingaApp / ginga  (composition roots: the only place that picks a VirtualDisplayBackend)
//        │
//        ├── GingaSession ──► VirtualDisplay, DisplayCapture, GingaCore
//        ├── CGVirtualDisplayBackend ──► VirtualDisplay, CGVirtualDisplayShim (Obj-C, private API)
//        │
//   VirtualDisplay   (Layer 1: abstraction + public CoreGraphics display APIs; no capture/UI/network)
//   DisplayCapture   (Layer 2: ScreenCaptureKit; consumes a CGDirectDisplayID only)
//   GingaCore      (clock, geometry, logging, statistics, process metrics)
import PackageDescription

let package = Package(
    name: "Ginga",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "GingaApp", targets: ["GingaApp"]),
        .executable(name: "ginga", targets: ["ginga"]),
    ],
    targets: [
        // Shared primitives. No dependency on any other module in this package.
        .target(name: "GingaCore"),

        // Layer 1 — Virtual Display Provider: the abstraction everything else depends on.
        .target(name: "VirtualDisplay", dependencies: ["GingaCore"]),

        // The ONLY code that knows about the private CGVirtualDisplay API (Objective-C so that
        // exceptions can be caught and selectors verified before use).
        .target(name: "CGVirtualDisplayShim", publicHeadersPath: "include"),

        // Path A backend: adapts the shim to `VirtualDisplayBackend`.
        .target(name: "CGVirtualDisplayBackend", dependencies: ["VirtualDisplay", "CGVirtualDisplayShim", "GingaCore"]),

        // Layer 2 — Display Capture (ScreenCaptureKit). Knows nothing about how the display was made.
        .target(name: "DisplayCapture", dependencies: ["GingaCore"]),

        // Layer 3 — Video Pipeline: VideoToolbox encode/decode, Annex-B, pacing. Independent of how
        // frames were produced (takes CVPixelBuffers + host timestamps).
        .target(name: "VideoPipeline", dependencies: ["GingaCore"]),

        // Wire protocol v1 (protocol/PROTOCOL.md): framing, messages, clock sync, golden vectors.
        // Foundation only — no platform frameworks, so it stays a pure contract implementation.
        .target(name: "GingaProtocol"),

        // Layer 4 — Transport: framed message connections (Network.framework TCP; AOA/Wi‑Fi later)
        // and the ADB bridge. Knows messages, not displays, capture or codecs.
        .target(name: "Transport", dependencies: ["GingaProtocol", "GingaCore"]),

        // Wiring of layers 1+2, configuration, self-test and benchmarks. Backend-agnostic.
        .target(name: "GingaSession", dependencies: ["VirtualDisplay", "DisplayCapture", "VideoPipeline", "GingaCore"]),

        // No-router mode (§6b): Bluetooth LE handover + joining the tablet's network (CoreWLAN).
        .target(name: "DirectLink", dependencies: ["GingaSecurity", "GingaCore"]),
        .testTarget(name: "DirectLinkTests", dependencies: ["DirectLink", "GingaSecurity", "GingaCore"]),

        // The composition shared by the app and `ginga run`.
        .target(
            name: "GingaRuntime",
            dependencies: ["GingaSession", "GingaStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "DisplayCapture", "Transport", "USBAccessory", "GingaSecurity", "DirectLink", "GingaProtocol", "GingaCore"]
        ),

        // Input forwarding (M5): gesture interpretation (pure) + CGEvent injection onto the virtual display.
        .target(name: "InputInjection", dependencies: ["GingaProtocol", "GingaCore"]),

        // Streaming: per-receiver sessions (handshake, encoder, backpressure, clock sync) over any
        // Transport, fed by a StreamHost (the virtual display, or a synthetic source for tests).
        .target(
            name: "GingaStreaming",
            dependencies: ["GingaSession", "VirtualDisplay", "DisplayCapture", "VideoPipeline", "Transport", "GingaProtocol", "GingaSecurity", "GingaCore"]
        ),

        // M7 Wi‑Fi security: self-signed TLS identities, fingerprints, pairing codes, pins.
        .target(name: "GingaSecurity", dependencies: ["GingaCore"]),

        // M6 direct USB: Android Open Accessory. The Objective-C shim is the only code calling
        // IOUSBHost (no Swift overlay exists); the Swift module holds the protocol and policy.
        .target(name: "USBAccessoryShim", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOUSBHost"), .linkedFramework("IOKit")]),
        .target(name: "USBAccessory", dependencies: ["USBAccessoryShim", "Transport", "GingaProtocol", "GingaCore"]),

        // Benchmarks only (linked by ginga, never by the app): SoC energy via IOReport (private,
        // resolved at runtime) and per-process CPU/energy/wake-ups via public libproc.
        .target(name: "EnergyMeter", dependencies: ["GingaCore"]),

        // Composition roots.
        .executableTarget(
            name: "GingaApp",
            dependencies: ["GingaSession", "GingaStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "DisplayCapture", "Transport", "USBAccessory", "GingaSecurity", "DirectLink", "GingaRuntime", "GingaCore"]
        ),
        .executableTarget(
            name: "ginga",
            dependencies: [
                "GingaSession", "GingaStreaming", "InputInjection", "VirtualDisplay", "CGVirtualDisplayBackend", "CGVirtualDisplayShim",
                "DisplayCapture", "VideoPipeline", "Transport", "GingaCore", "GingaProtocol", "EnergyMeter", "USBAccessory",
                "GingaSecurity", "GingaRuntime",
            ]
        ),

        // Test support: Objective-C fakes that mimic the private classes' exact selectors/type encodings.
        .target(name: "ShimFakes", path: "Tests/ShimFakes", publicHeadersPath: "include"),
        // Test support: simulated WindowServer / backend for the provider and session tests.
        .target(name: "VirtualDisplayTestSupport", dependencies: ["VirtualDisplay", "GingaCore"], path: "Tests/VirtualDisplayTestSupport"),

        .testTarget(name: "GingaCoreTests", dependencies: ["GingaCore"]),
        .testTarget(name: "VirtualDisplayTests", dependencies: ["VirtualDisplay", "VirtualDisplayTestSupport", "GingaCore"]),
        .testTarget(
            name: "CGVirtualDisplayBackendTests",
            dependencies: ["CGVirtualDisplayBackend", "CGVirtualDisplayShim", "ShimFakes", "VirtualDisplay", "GingaCore"]
        ),
        .testTarget(name: "DisplayCaptureTests", dependencies: ["DisplayCapture", "GingaCore"]),
        .testTarget(name: "GingaProtocolTests", dependencies: ["GingaProtocol"]),
        .testTarget(name: "VideoPipelineTests", dependencies: ["VideoPipeline", "GingaCore"]),
        .testTarget(name: "TransportTests", dependencies: ["Transport", "GingaProtocol", "GingaSecurity", "GingaCore"]),
        .testTarget(name: "InputInjectionTests", dependencies: ["InputInjection", "GingaProtocol"]),
        .testTarget(name: "EnergyMeterTests", dependencies: ["EnergyMeter", "GingaCore"]),
        .testTarget(name: "GingaSecurityTests", dependencies: ["GingaSecurity"]),
        .testTarget(name: "USBAccessoryTests", dependencies: ["USBAccessory", "USBAccessoryShim", "Transport", "GingaProtocol"]),
        .testTarget(name: "GingaAppTests", dependencies: ["GingaApp"]),
        .testTarget(
            name: "GingaStreamingTests",
            dependencies: [
                "GingaStreaming", "GingaSession", "VirtualDisplay", "VirtualDisplayTestSupport", "DisplayCapture",
                "VideoPipeline", "Transport", "GingaProtocol", "GingaSecurity", "GingaCore",
            ]
        ),
        .testTarget(
            name: "GingaSessionTests",
            dependencies: ["GingaSession", "VirtualDisplay", "VirtualDisplayTestSupport", "DisplayCapture", "GingaCore"]
        ),
    ]
)
