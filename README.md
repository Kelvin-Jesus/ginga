# Ginga (internal name: Ginga)

Ginga turns a **Samsung Galaxy Tab S11 into a real second display for an Apple Silicon Mac**. It is an independent project in the spirit of Sidecar and Duet. The apps show only "Ginga"; Ginga stays the name of the code (modules, `ginga`, logs, bundle id). Brand and design system: [brand/README.md](brand/README.md), [design/ginga-design/](design/ginga-design/HANDOFF.md).

macOS gets a genuine extended display:

- it has its own `CGDirectDisplayID`;
- it is listed in System Settings › Displays;
- windows can be dragged onto it;
- it has configurable resolution, scaling, refresh rate, orientation and position.

Ginga captures that display (and only that display), hardware-encodes it and streams it to the tablet. Touch and S Pen input go back to the Mac.

```text
Mac:     Virtual Display → Capture → Hardware Encode → Transport ─┐
Android:                    Render ← Hardware Decode ← Transport ←┘ → Input → Mac
```

## Status

| Milestone | State |
|---|---|
| M0 Research & architecture | ✅ [research](docs/research.md) · [architecture](docs/architecture.md) · [plan](docs/milestones.md) |
| **M1 Virtual display + capture + Mac debug preview** | ✅ Signed off on an M4 / macOS 26.6.2: every acceptance check passes, including capture of the virtual display at 2560×1600 (117.7 fps at 120 Hz) |
| M2 Hardware encoder | ✅ VideoToolbox HEVC, 5.9 ms p50 at 2560×1600 (sustains 120 fps) |
| M3 Protocol v1 + transport | ✅ Wire protocol with 32 golden vectors shared with Android; TCP transport; streaming server; loopback tests |
| M4 Android receiver over USB | ✅ The Mac's virtual display streams to the Tab S11 over USB at **60 fps, 0 dropped, end-to-end p50 8–17 ms** (measured on the device); pause/resume when the tablet app is in the background |
| M5 Touch and S Pen | ✅ Verified on the device: touch clicks and drags land exactly; the S Pen is a pen tablet to macOS (proximity, pressure, tilt, eraser), as Sidecar makes the Apple Pencil |
| Power | ✅ Measured per change (`ginga bench-power`, IOReport, no root): a 60 Hz display streaming continuous animation adds ~230 mW, and a static desktop adds ~0. See the energy section of [performance](docs/performance.md) |
| M6 Direct USB (Android Open Accessory) | ✅ Verified on the device and now the default link: **120 fps at 120 Hz with 0 dropped frames, end-to-end p50 ≈ 13 ms**; no developer mode or adb; only approved tablets get a session |
| M7 Wi‑Fi | ✅ Verified on the device: Bonjour, TLS 1.3 with pinned certificates, numeric-comparison pairing with commitments, 60 fps with 0 dropped frames |
| M8 Wi‑Fi UDP · M9 Polish | Planned |

**M1 on hardware** (`ginga verify` and `Ginga.app --self-test`):

- A "Galaxy Tab S11" display is created with its own ID, next to the built-in panel and an external monitor, and it extends the desktop.
- AppKit and System Information both see it, at 1280×800 @2x (2560×1600 px, pixel-exact for the Tab S11).
- A window moves from the built-in display onto it and back.
- Resolution and orientation changes apply live on the same display.
- It is removed cleanly.

## Quick start

Requirements: Apple Silicon Mac with macOS 14+ (tested on 26.6.2), and Swift 6 (Xcode or just the Command Line Tools).

```sh
cd mac
scripts/test.sh                      # unit tests (swift-testing; works without Xcode)
scripts/build-app.sh                 # → build/Ginga.app, build/ginga

build/ginga probe                      # is the private virtual-display API usable on this macOS?
build/ginga verify --no-capture        # M1 acceptance checks (adds a display for ~5 s)
open build/Ginga.app               # control panel + menu bar: Create Display, Show Debug Preview
```

**Screen Recording is needed for capture.** Grant it to Ginga under System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch. With ad-hoc signing the grant resets on every rebuild; run `scripts/create-dev-signing-identity.sh` once to avoid that (see [development.md](docs/development.md)).

## How it works

| Layer | Implementation |
|---|---|
| 1 · Virtual Display Provider | The private `CGVirtualDisplay` API, sealed behind `VirtualDisplayBackend`. One Objective‑C file verifies every selector and signature at runtime and turns exceptions into errors. Mode selection, arrangement and monitoring use public CoreGraphics. See [virtual-display-backend.md](docs/virtual-display-backend.md). |
| 2 · Display Capture | ScreenCaptureKit on that `CGDirectDisplayID` only: `420v` BT.709 IOSurfaces straight into the encoder (zero-copy), frames only when content changes, and capture only while a tablet (or the debug preview) is watching |
| 3 · Video Pipeline | VideoToolbox HEVC, no frame reordering (5.9 ms p50 at 2560×1600 on M4; power-efficient mode on battery), latest-frame-wins pacing, live bitrate |
| 4 · Transport | USB through `adb reverse` (TCP on 127.0.0.1:47800, kept in place automatically) or directly as an Android Open Accessory (no developer mode); Wi‑Fi over TLS with pairing. UDP with FEC comes later. One protocol on every link: [PROTOCOL.md](protocol/PROTOCOL.md) |
| 5 · Android (M4+) | Kotlin, MediaCodec low-latency decode into a SurfaceView, touch and S Pen capture |

**No public macOS API creates a display.** DriverKit has no display family, including in macOS 27. So Ginga uses a private API, which rules out the Mac App Store; distribute it signed with Developer ID and notarized. Kernel extensions, SIP changes or WindowServer patching are never used.

## Repository

```text
docs/        setup · configuration · research · architecture · milestones · virtual-display-backend · development · troubleshooting · performance
protocol/    wire protocol v1 + golden test vectors shared by the Swift and Kotlin suites
config/      example configuration files
mac/         Swift package: GingaCore, VirtualDisplay, CGVirtualDisplayShim, CGVirtualDisplayBackend,
             DisplayCapture, VideoPipeline, GingaProtocol, Transport, USBAccessoryShim, USBAccessory,
             GingaSecurity, DirectLink, GingaStreaming, InputInjection, GingaSession,
             GingaRuntime, EnergyMeter, GingaApp (app), ginga (CLI, incl. headless `ginga run`), Tests
scripts/     bootstrap.sh (environment), check-all.sh (both suites + vectors), docker-android.sh
.claude/     slash commands for agents (check-all, protocol-change, device-test); see CLAUDE.md
brand/       Ginga brand: logos, app-icon source, colours, usage rules
android/     Kotlin receiver app (Gradle modules: protocol, transport, decoder, renderer, input, discovery, app)
```

## Documentation

- [Guide for agents](CLAUDE.md) · [status](docs/status.md) · [known issues](docs/known-issues.md) · [roadmap](docs/roadmap.md) · [diagrams](docs/diagrams.md)
- [Setup: Mac + Galaxy Tab S11](docs/setup.md)
- [Configuration reference (`config.json`)](docs/configuration.md)
- [Research: platform constraints, APIs, measurements](docs/research.md)
- [Architecture and decision log](docs/architecture.md)
- [Implementation plan and milestone gates](docs/milestones.md)
- [Virtual display backend boundary (private API containment)](docs/virtual-display-backend.md)
- [Development guide: build, test, run, sign, log](docs/development.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Performance and benchmarks](docs/performance.md)
- [Protocol v1](protocol/PROTOCOL.md)

## Limitations

- The private API can change with any macOS update. `ginga probe` and the canary test detect it, and the app refuses to proceed rather than crash. Tested on macOS 26.6.2 only so far.
- macOS 15+ asks for monthly re-confirmation of screen capture, unless Apple grants the persistent-content-capture entitlement.
- DRM-protected content captures black, and nothing is captured at the lock screen.

## License

Ginga is free software: you can redistribute it and/or modify it under the terms of the **GNU Affero General Public License, version 3** ([LICENSE](LICENSE), SPDX `AGPL-3.0-only`). Any fork or modified version you distribute, or let people use over a network, must be released under the same license with its complete source code. The author can also offer the software under other terms.

Not covered by the AGPL: the brand fonts in `brand/fonts/` (SIL Open Font License 1.1, their licenses alongside) and the Ginga name and marks, which identify this project: forks must use another name and logo. See [NOTICE](NOTICE).
