# Implementation plan

Small milestones, each with a test and benchmark gate. **No milestone starts until the one before it passes its acceptance criteria on real hardware.** This follows the brief's rule: no Android, networking, USB or input work until the virtual display works.

| # | Milestone | Status |
|---|---|---|
| M0 | Research, spike, architecture | ✅ done ([research](research.md), [architecture](architecture.md)) |
| M1 | Virtual display + capture + local debug preview | ✅ **signed off on hardware**: every acceptance check passes, including capture (see below) |
| M2 | Video pipeline on the Mac (hardware encode, local decode loopback) | ✅ Mac side: `VideoPipeline`; encode benchmark; loopback decode in tests. The "encoded" preview view is still to do |
| M3 | Protocol v1 + transport abstraction + Mac loopback receiver | ✅ `Tab2MacProtocol` with golden vectors (32 now), TCP `Transport`, `Tab2MacStreaming`, and end-to-end loopback tests |
| M4 | Android receiver MVP over USB (ADB reverse) | ✅ **Gate met on the device:** the real virtual display at 60 fps, 0 dropped, end-to-end p50 8–17 ms (gate: ≤ 40 ms). Pause/resume verified ([performance](performance.md)) |
| M5 | Touch and S Pen input forwarding | ✅ Verified on the device: touch lands exactly; the S Pen is a pen tablet (proximity, pressure, tilt, eraser) |
| P | Power, cross-cutting (the reference is Sidecar) | ✅ Energy measured per change (`t2m bench-power`, `bench-encode --sweep`): 60 Hz default, capture only on demand, event-driven adb, pause protocol, battery-aware encoder. See [performance](performance.md) |
| M6 | Direct USB transport (Android Open Accessory) + auto-detect | ✅ Verified on the device and the default link: 120 fps at 120 Hz, 0 dropped, end-to-end p50 ≈ 13 ms (adb: ~1.7 % dropped). Only approved tablets get a session; the tablet reconnects by itself while plugged in. Gate met: the link sustains the full 120 Hz stream |
| M7 | Wi‑Fi: discovery, pairing, TCP profile, adaptive bitrate, reconnection | ✅ Verified on the device: Bonjour (resolved again before every connection), TLS 1.3, numeric-comparison pairing with commitments (PROTOCOL.md §6), 60 fps with 0 dropped. A tablet that no longer knows the Mac asks to pair again (`pairingRequested`) |
| M8 | Wi‑Fi UDP profile: FEC, NACK, LTR/IDR recovery | |
| M9 | Polish: cursor overlay, orientation sync, idle refinement, packaging | 🔄 Cursor as a side channel (§3.3b) and the S Pen as a pen tablet are done; idle refinement and packaging remain |

The user asked on 2026‑09‑25 to develop Android in parallel, which lifted the original "Mac first" gate. M1 was signed off the same day.

---

## M1 — Virtual display, capture, local preview

**Scope (per brief):**

1. Create one virtual display.
2. It appears in Displays settings.
3. The desktop extends onto it.
4. Obtain its display ID.
5. Capture frames from it.
6. Show the frames in a debug window on the Mac.

**Delivered:**

- Layer 1: `VirtualDisplay`, `CGVirtualDisplayBackend` and `CGVirtualDisplayShim` (the private API isolated and runtime-verified).
- Layer 2: `DisplayCapture` (ScreenCaptureKit).
- The session and configuration.
- `Tab2Mac.app`: control panel, menu bar item, and a debug preview with a diagnostics overlay.
- The `t2m` CLI: `probe`, `displays`, `create`, `verify`, `bench-capture`.
- The M1 verifier and the capture benchmark.
- Example configs.

**Automated tests:**

- 145 swift-testing tests in 24 suites: 29 core, 53 virtual-display, 27 backend/shim, 20 capture, 16 session.
- Two of them are gated: a real-display integration test (`T2M_INTEGRATION=1`) and a real-capture test (which also needs Screen Recording).

**Acceptance:**

| Criterion | Check | Result on Mac16,1 / macOS 26.6.2 |
|---|---|---|
| Display created, own `CGDirectDisplayID` | `verify`: `display-created`, `independent-display-id` | ✅ (e.g. ID 16/17 next to 1 and 2) |
| Listed in Displays settings | `verify`: `system-information`; open System Settings › Displays | ✅ "Galaxy Tab S11" listed |
| Extends desktop | `verify`: `extends-desktop`, `appkit-screen` | ✅ own `NSScreen`, 1280×800 @2x |
| Windows move built-in ↔ virtual | `verify`: `window-moves` (1 → 17 → 1); plus manual drag | ✅ automated; manual check pending |
| Resolution, scaling, refresh, orientation, position configurable | `verify`: `target-mode`, `live-mode-change`, `live-orientation-change`; UI | ✅ |
| Capture frames of that display only | `verify`: `capture` (≥10 fps with load, expected pixel size) + PNG snapshot | ✅ 120 frames in 2 s at 2560×1600; the snapshot shows the virtual display's own desktop and test window |
| Debug window shows the frames | App › Show Debug Preview | ✅ implemented; manual look pending |
| Display exists without any consumer | Display is created and verified with capture disabled | ✅ |

**Sign-off steps for you:**

1. Run `mac/scripts/build-app.sh`. Optionally run `create-dev-signing-identity.sh` first, so the grant survives rebuilds.
2. Open `mac/build/Tab2Mac.app` and click **Grant…** under Screen Recording. Enable Tab2Mac in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch the app.
3. Click **Create Display**, drag a window from the MacBook screen onto "Galaxy Tab S11", and click **Show Debug Preview**. You should see that window in the preview, with live statistics.
4. Run the headless self-test and capture benchmark (commands in [development.md](development.md#m1-sign-off)) and keep the JSON reports.

**Gate to M2:** all eight criteria pass (✅), and capture sustains the display rate: 117.7 fps at 120 Hz and 60.0 fps at 60 Hz. An early 60 Hz run showed 10–22 fps; that was a harness bug (the load window landed on another display), not macOS. The display defaults to 60 Hz for power (ADR‑14); see [performance](performance.md).

---

## M2 — Video pipeline (Mac only)

**Build:**

- `VideoPipeline`:
  - a `VTCompressionSession` wrapper for HEVC normal mode and H.264 low-latency (settings from research §3);
  - latest-frame-wins pacing;
  - forced keyframes, live bitrate changes, idle refinement;
  - Annex‑B / length-prefixed NAL conversion and parameter-set extraction.
- A local loopback: encoded frames are decoded by `VTDecompressionSession` and shown in the debug preview ("encoded view"). This proves the whole Mac-side pipeline without any network.

**Tests:**

- Encoder configuration mapping.
- NAL/parameter-set parsing (fixtures).
- Pacing queue behaviour (drop counts, ordering).
- Keyframe on request.
- Bitrate updates applied.

**Benchmarks (`bench-encode`):**

- Encode latency p50/p95 at 1280×800@2x (2560×1600) and at 60/120 Hz.
- Bitrate vs quality: bytes per frame for idle, text scrolling and video.
- CPU, GPU and memory.

**Gate:** encode p95 ≤ 8 ms at 2560×1600@60, no sustained drops under the load generator, and the loopback view is visually lossless for text.

## M3 — Protocol v1 + transport abstraction + Mac loopback receiver

**Build:**

- A `Protocol` module:
  - framing, the JSON control messages, the binary hot-path messages, and the clock-sync math;
  - **golden vectors** in `protocol/test-vectors/`.
- A `Transport` module: `MessageChannel`, a TCP implementation (Network.framework), and a connection state machine with reconnection.
- A `t2m receive` loopback client that decodes and displays, so end-to-end runs work on one Mac.

**Tests:**

- Codec round-trips and golden vectors.
- Partial reads and coalesced frames.
- Fuzzing: truncated, oversized and unknown message types.
- Version negotiation.
- Backpressure: a slow receiver never grows the queues.

**Benchmarks:** loopback throughput and latency (capture → loopback render, clock-free since it's the same host).

## M4 — Android receiver MVP over USB (ADB reverse)

**Build:**

- The Kotlin project (Gradle, AGP; JDK 17 is present via Homebrew; Android SDK to be installed).
- `:protocol` (golden vectors shared with the Mac), `:transport` (TCP via `adb reverse`), `:decoder` (MediaCodec low latency), `:renderer` (SurfaceView), and `:app` (connect/disconnect, status, diagnostics overlay).
- Clock sync and per-frame end-to-end latency.

**Tests:**

- JVM unit tests for the protocol (the same vectors), the decoder configuration builder, and the reconnection policy.
- An instrumented decode test with a recorded HEVC fixture.

**Benchmarks:** end-to-end latency p50/p95, decode latency (MediaTek risk), dropped frames, battery drain per hour on the tablet.

**Gate:** a live extended desktop on the Tab S11, with end-to-end p50 ≤ 40 ms at 60 Hz over USB/ADB.

## M5 — Input forwarding

**Build:**

- Android `:input`: touch and S Pen with pressure, tilt, hover and buttons; `requestUnbufferedDispatch`.
- A Mac `InputInjection` module: CGEvent mapping (architecture §2.7), requesting Post Event access on first use.

**Tests:**

- Coordinate mapping for all orientations and scalings.
- The gesture state machine: tap, drag, long-press, two-finger scroll with phases.
- Pen mapping.

**Benchmarks:** input-to-photon latency using the load window's timestamp.

## M6 — Direct USB: Android Open Accessory

**Build:**

- An IOUSBHost matcher for the Samsung VID, with the AOA handshake (51/52/53) and the re-enumeration wait.
- Bulk pipes, with 16 KB-aligned writes and ZLP handling.
- Android `UsbAccessory` with an accessory filter.
- Automatic connect when plugged in, and fallback to ADB.

**Gate benchmark:** host→device throughput must be ≥ 3× the target bitrate, measured with the real Tab S11. Otherwise ADB stays the primary transport (ADR‑6).

## M7 — Wi‑Fi: discovery, pairing, TCP, adaptive bitrate

**Build:**

- Bonjour advertising (`NWListener.service`, `_tab2mac._tcp`) and `NsdManager` discovery.
- TLS 1.3 pairing with numeric comparison.
- The TCP profile.
- Receiver reports and AIMD bitrate control; the low-latency Wi‑Fi lock.
- Reconnection and the display-keep policy.

**Tests:**

- The pairing state machine.
- The bitrate controller against synthetic delay/loss traces.
- Discovery TXT parsing.

**Benchmarks:** end-to-end latency on Wi‑Fi 6E vs 5, and bitrate adaptation under `dnctl`-injected delay and loss.

## M8 — Wi‑Fi UDP profile

**Build:**

- Fragmentation (≤ 1200-byte packets) and Reed–Solomon FEC.
- NACK within the deadline, then LTR (H.264) or IDR recovery.
- AES‑GCM keyed from the TLS exporter.

**Tests:** FEC encode/decode, reordering and loss simulation, replay protection.

**Benchmarks:** loss recovery rate and latency at 1/5/10% loss.

## M9 — Polish

- A cursor side channel with Android-side rendering.
- Tablet rotation drives the virtual display's orientation.
- Idle quality refinement.
- ~~App Nap and power assertions while streaming~~ (done: a latency-critical activity is held only while a tablet is connected).
- A cursor overlay for power: pointer motion over static content should cost a small message, not a re-encoded frame.
- AOA (M6) also saves power: `adb reverse` relays every video byte through the adb server on the Mac and adbd on the tablet. Measure that relay with `t2m energy` during a USB stream.
- Multiple-tablet identities.
- Packaging: Developer ID signing, notarization, and optionally applying for the persistent-content-capture entitlement.
- Documentation updates.
