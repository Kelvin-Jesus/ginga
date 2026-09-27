# Performance and benchmarks

## Budgets

The goal is the lowest possible latency. The wired end-to-end target is p50 ≤ 30 ms and Wi‑Fi ≤ 50 ms, from composition on the Mac to light on the tablet. Stage budgets are in [architecture.md §3](architecture.md#latency-budget-wired-target-p50).

Every benchmark report includes host information (model, chip, macOS build) and is written as JSON, so runs can be compared over time.

## Benchmark suite

| Benchmark | Command | Measures | Milestone |
|---|---|---|---|
| Virtual display lifecycle | `t2m verify --no-capture --report r.json` | Per-step durations: create → online, mode switch, orientation change, removal | M1 ✅ |
| Capture | `open -W -n --stdout out.txt mac/build/Tab2Mac.app --args --benchmark-capture --seconds 10 --report r.json [--config c.json]` (or `t2m bench-capture` from a terminal that has Screen Recording) | See the list below this table | M1 ✅ |
| Encode | `t2m bench-encode [--codec hevc\|h264] [--fps N] [--size WxH]` | Encode latency p50/p95/p99, bytes per frame, achieved bitrate, CPU | M2 ✅ |
| Stream on one Mac (loopback) | `t2m serve --synthetic` (or the app with the tablet server on), then `t2m receive --seconds N --report r.json` | Received and decoded fps, display → received and display → decoded latency on one clock, irregular frame intervals | M3/M4 ✅ |
| End to end on the tablet | The tablet's RECEIVER_REPORT, logged by the Mac once a second (`stream.report`) | Capture → rendered latency per frame (clock sync), decode latency, dropped frames, fps | M4 ✅ |
| Energy | `t2m bench-power` (scenario matrix), `t2m energy` (one reading), `t2m bench-encode --sweep` | SoC energy per component (IOReport: CPU, GPU, encoder, memory, display), per-process energy | P ✅ |
| Direct USB throughput | Not automated yet | MB/s host → device over the accessory's bulk pipes | M6 |
| Input | Load-window timestamps + touch | Input-to-photon latency | M5 |
| Impaired Wi‑Fi | `dnctl` / `pfctl` dummynet profiles | Bitrate adaptation, recovery time, residual loss | M7/M8 |

**What the capture benchmark measures:**

- Frames delivered and the average FPS.
- Frame-interval jitter.
- Delivery time vs the frame's display time (vsync), p50/p95/p99. Negative means the frame arrived before its vsync.
- Process CPU and memory footprint, and system GPU utilisation — both **baseline** (display + animated load, no capture) and **while capturing**.

**How the capture benchmark works:**

1. It creates the virtual display and puts an animated window on it. Core Animation updates it every refresh, so WindowServer composes a new frame each vsync.
2. It samples resources for a baseline period without capture.
3. It captures for N seconds with a frame sink that releases buffers immediately.
4. CPU is process user+system time per wall second (100% = one core). Memory is `phys_footprint`, matching Activity Monitor. GPU is the IORegistry `PerformanceStatistics › Device Utilization %` — system-wide, since macOS has no per-process GPU metric.

## Results

### M1 — virtual display lifecycle (Mac16,1 M4, macOS 26.6.2)

| Step | Duration |
|---|---|
| Create → online → mode selected (first display in a process) | 753 ms (`-applySettings:` 77–350 ms in isolation) |
| Live resolution/scale change, round trip (2 switches) | 692 ms |
| Live orientation change, round trip (2 re-modes) | 742 ms |
| Removal until offline | 355 ms |

Source: the `Tab2Mac.app --self-test` report of 2026‑09‑25.

### M1 — capture (2026‑09‑25, `Tab2Mac.app --benchmark-capture`, 10 s)

The virtual display renders "looks like 1280×800 @2x" and is captured at 2560×1600 `420v`, with an animated load window on it.

| Display refresh → stream rate | Captured fps | Frame interval | Delivery vs display time | Process CPU (baseline → capturing) | Process memory | System GPU (capturing) |
|---|---|---|---|---|---|---|
| 120 Hz, uncapped | **117.7** | 8.3 ms (p95 8.3) | −6.6 ms (p95 −5.3) | 0.8% → **4.6%** | 18.7 MB | 36% |
| 120 Hz → capped at 60 (the default at the time; now 60 Hz, ADR‑14) | 65.7 at the source; the stream limiter sends 60 | 15.1 ms (p95 16.7) | −2.6 ms | 1.0% → **3.2%** | 18.8 MB | 25% |
| 60 Hz | ~~5.9–22~~ measurement bug, see below; re-measured end to end: **60.0** | 16.7 ms (p95 16.7) | — | — | — | — |

**Findings:**

- **Correction: 60 Hz displays compose normally.** The 5.9–22 fps row was a harness bug. The load window was created with `NSWindow(contentRect:…, screen:)`, which reads the rect relative to that screen, so the window landed on another display. Most "frames" were then SCK idle frames. With the window placed by its global frame, a 60 Hz display streams 60.0 fps at a 16.7 ms p95 interval. The load window also requests the display's full rate (`preferredFrameRateRange`); without it, Core Animation ran it at 60 fps even on a 120 Hz display.
- **"Delivery vs display time" is negative.** ScreenCaptureKit's `displayTime` is the vsync a frame is composed *for*, and frames reach us 2–7 ms *before* that vsync. Capture therefore adds no latency compared with a local monitor. End-to-end latency uses the same timestamp, so it reads as "later than a local monitor by X ms".
- **Cost of capture:** about 3–4% of one core and under 2 MB of extra memory at 2560×1600, 60–120 fps. The GPU figure is system-wide and includes the animated load window.

### M2 — encode (2026‑09‑25, `t2m bench-encode`, release build, 600 frames, synthetic moving pattern)

| Codec @ rate | p50 | p95 | p99 | max | CPU (process) |
|---|---|---|---|---|---|
| HEVC 2560×1600 @60 | **5.87 ms** | 6.22 ms | 6.31 ms | 9.45 ms | 8.5% |
| HEVC 2560×1600 @120 | **5.80 ms** | 6.15 ms | 11.05 ms | 21.11 ms | 10.3% |
| H.264 2560×1600 @60 | 8.95 ms | 9.33 ms | 9.53 ms | 16.52 ms | 8.3% |

**Findings:**

- The hardware HEVC encoder keeps up with 120 fps at the Tab S11's native resolution, with a p95 around 6 ms. HEVC is faster than H.264 on the M4, which confirms ADR‑5.
- The CPU figure includes the benchmark's own pacing loop.
- Bitrate figures from this synthetic pattern aren't representative (it compresses to almost nothing). Real desktop content is measured in the end-to-end runs (M4).

### Energy (2026‑09‑25, `t2m bench-power`, M4 MacBook Pro, macOS 26.6.2)

Power is an acceptance criterion; the reference is Sidecar. `t2m bench-power` launches the app per scenario and streams an animated test window (Core Animation moving every vsync plus a clock, the worst case) to a receiver on the same Mac. Each run measures a 20 s steady-state window. Mean of 2 interleaved runs:

| Scenario (display → stream) | Stream fps | Frame interval p95 | Δ SoC vs idle | Encoder (AVE) | Tab2Mac CPU / energy | replayd CPU | WindowServer CPU |
|---|---|---|---|---|---|---|---|
| Idle Mac, no Tab2Mac | – | – | 0 | – | – | – | 24.7 % |
| **60 Hz → 60 fps (default)** | **60.0** | **16.7 ms** | **+229 mW** | ~120 mW | 7.6 % / 5 mW | 3.1 % | 43.8 % |
| 120 Hz → 60 fps, frames dropped in-process | 60.0 | 16.7 ms | +672 mW | ~120 mW | 8.2 % / 8 mW | 5.1 % | 56.8 % |
| 120 Hz → 60 fps, ScreenCaptureKit drops frames (old default) | 51.0 | 33.3 ms | +408 mW | ~110 mW | 6.6 % / 5 mW | 3.1 % | 55.4 % |
| 60 Hz → 60 fps, BGRA capture | 60.0 | 16.7 ms | +448 mW | ~120 mW | 12.1 % / 11 mW | 3.1 % | 41.9 % |
| 120 Hz → 120 fps (opt-in; separate run, 3×) | 119.7 | 8.3 ms | ≈ +830 mW **over 60 Hz → 60** | 188 mW | 10.5 % / 16 mW | 3.9 % | 55.6 % |
| Static desktop, 60 Hz, receiver connected | 0 | – | ≈ 0 for Tab2Mac (0.2 % CPU, 0 mW, 0 wake-ups/s) | – | 0.2 % / 0 mW | 0.2 % | see below |

System-wide figures include everything else running (a browser, the Android build), so trust the per-process and encoder columns most. Conclusions:

- **60 Hz is the default** (ADR‑14). The old default was 120 Hz with ScreenCaptureKit dropping every other frame: it cost +408 mW and delivered only 51 fps with 33 ms gaps. A regular 60 fps from a 120 Hz display costs +672 mW. 60 Hz delivers a regular 60 fps for +229 mW. At 120 Hz, WindowServer composes twice as often, apps on the display render twice as often, and twice as many frames are converted. 120 Hz → 120 fps remains an opt-in: 120.7 fps at an 8.33 ms p95 interval, display → decoded p50 3.3 ms. It costs about 0.8 W more than 60 Hz on the Mac: GPU +300, memory +320 and encoder +63 mW. The bitrate is 2.4× higher, which the tablet must also decode.
- **Let ScreenCaptureKit drop frames? No.** It judges by jittery delivery times, so 120 → 60 comes out at 51 fps with 33 ms gaps. When a cap applies, `FrameCadence` picks frames on capture timestamps instead.
- **Tab2Mac's own process is not where the energy goes.** It uses about 5 mW at 60 fps (7 % of one core, about 20 wake-ups/s). A profile shows no hot spot beyond per-frame dictionary lookups and socket writes. The cost sits in the system: WindowServer composition, ScreenCaptureKit's conversion (GPU and memory traffic), and the encoder.
- **Keep `420v` capture.** With BGRA, the encoder converts in our process: +5 % CPU and about twice the system power.
- **Nothing runs when nothing changes.** With a static desktop, the stream sends nothing and Tab2Mac sits at 0 wake-ups/s. The adb bridge is event-driven, diagnostics sample only while visible, and capture stops when no tablet or preview is watching.
- **The idle virtual display itself costs WindowServer little** (static 60 vs 120 Hz: 37.3 vs 38.0 % CPU). The larger idle cost seen here came from macOS switching the *HDMI monitor* from 60 Hz to 100 Hz when the display set changed ([troubleshooting](troubleshooting.md)).

**Encoder hints** (`t2m bench-encode --sweep`, 2560×1600 @60, synthetic source):

| Setting | Encode p50 / p95 | Encoder (AVE) power |
|---|---|---|
| Default (normal mode, ExpectedFrameRate 2×) | 5.9 / 6.2 ms | 112 mW |
| ExpectedFrameRate 1× | 5.9 / 6.2 ms | 118 mW |
| `MaximizePowerEfficiency` | 12.1 / 12.5 ms | **69 mW** |
| `RealTime` | 11.8 / 12.4 ms | 80 mW |

`streaming.encoderPower` is `automatic` by default: lowest latency on AC power, and `MaximizePowerEfficiency` on battery (−40 % encoder power for +6 ms). It switches live when the power source changes (a new encoder and a keyframe). `lowest-latency` and `lowest-power` pin either choice.

### M4 — the real path on the Tab S11 (2026‑09‑26)

Path: virtual display (60 Hz, test window) → ScreenCaptureKit → HEVC 2560×1600 → TCP → `adb reverse` → USB → MediaCodec (`c2.mtk.hevc.decoder.lowlatency`) → SurfaceView. The figures below are the tablet's RECEIVER_REPORTs over 8 s, one per second:

| Metric | Value |
|---|---|
| Frame rate | **60 fps** (58–61 per report), **0 dropped** |
| End-to-end p50 (Mac vsync → rendered on the tablet) | **8–17 ms** |
| End-to-end p95 | 12–53 ms |
| Decode p50 (tablet) | 12.7–15.3 ms |
| RTT (clock sync) | 2–5 ms (one 48 ms outlier) |

Mac while streaming (`t2m energy`, 20 s):

| Component | Cost |
|---|---|
| Tab2Mac | 8 % CPU, 10 mW, 42 wake-ups/s |
| Encoder (AVE) | 125 mW |
| replayd | 2.8 % CPU, 4 mW |
| adb server relaying the stream | 2.6 % CPU, **2 mW** |

AOA's advantage over adb is therefore mostly UX (no developer mode, auto-launch), not power.

**Pause, measured on device.** The tablet app was sent to the background: Tab2Mac dropped to **0.1 % CPU, 0 mW, 2 wake-ups/s**, and capture stopped (replayd 0 %). On return, the stream resumed at 60 fps with a keyframe and no drops.

The screenshot taken on the tablet shows the Mac's virtual display with its wallpaper, the test window and the Mac's cursor.

### 120 Hz stability (2026‑09‑26, app → `t2m receive --warmup 3 --seconds 40`, same Mac)

A 120 Hz display streams 120 fps of continuous Core Animation motion. The receiver decodes with VideoToolbox on the same clock.

| | Before | After |
|---|---|---|
| Frames | 4680 in 38.9 s (120.3 fps) | 4803 in 40.1 s (**119.9 fps**) |
| Keyframes | 4 (one every 10 s) | **1** (session start only) |
| Frame interval p50 / p95 / max | 8.3 / 8.3 / 200 ms | 8.3 / 8.3 / **16.7 ms** |
| Irregular intervals (> 1.5× median) | 3 | 3 in 4800 (0.06 %), each one frame long |
| Display → decoded p50 / p95 / max | 2.5 / 4.6 / 311 ms | **2.7 / 5.0 / 14.3 ms** |
| Encode p50 / p95 / max | 6.8 / 7.3 / 30.9 ms | 6.9 / 7.2 / **8.6 ms** |

Two changes made the difference:

- **No periodic keyframes.** Every link is reliable, and the tablet requests a keyframe when it misses a frame, so the IDR "safety net" every 10 s only cost a bitrate spike. At 2560×1600 an IDR also encodes in up to 31 ms, far over the 8.3 ms frame time. Careful: VideoToolbox reads `MaxKeyFrameInterval = 0` as its default GOP of about 30 frames (156 IDRs in 39 s were measured), not as "no limit". Huge values are set instead, and a test pins the behaviour.
- **Two frames may be in the encoder** (`FramePacer(maxInFlight: 2)`). One slow encode then delays the next frame instead of dropping it.

The remaining pacer drops happen during warm-up: encoder creation and the first IDR.

**Since that run (2026‑09‑26, not yet re-measured on the device):**

- At the display's own rate, `FrameCadence` now steps aside entirely. A capture timestamp that arrived late used to re-anchor its schedule, and the next on-time frame then looked early and was skipped: a synthetic 120 Hz source lost about 1 frame in 120 that way, and loses none now (a regression test pins it).
- **To try:** `capture.queueDepth` 6 at 120 Hz. Up to four capture surfaces can be held at once (one waiting for the encoder, two inside it, and the latest kept for keyframes on a static screen), which leaves ScreenCaptureKit one of its five. Measure with `t2m receive` before changing the default: a deeper pool costs memory (about 6 MB per 2560×1600 surface), not energy per frame.

### 120 Hz on the Tab S11: direct USB vs adb (2026‑09‑26, tablet reports, 20 s each)

The same stream (virtual display at 120 Hz, animated test window, HEVC 2560×1600) over both USB links, measured by the tablet's RECEIVER_REPORTs:

| Link | Rendered | Dropped on the tablet | End-to-end p50 / p95 | RTT |
|---|---|---|---|---|
| **Direct USB (AOA)** | **120.2 fps** (2405 in 20 s) | **0** | **12.3–13.0 / ≤ 16.5 ms** | 0.5–2.3 ms |
| adb reverse | ~118 fps | 1–3 per second (~1.7 %) | 12.7–14.0 / 15–30 ms | 2–5 ms, 45 ms spikes every ~4 s |

The Mac delivers 120 frames per second either way. adb's relay (adb server → adbd) delivers them in bursts, the RTT spikes show when, and the tablet keeps only the newest of two frames that decode in the same vsync. Direct USB has no relay. That is why it is now the default and the recommended link.

The S Pen was verified the same day as a pen tablet (proximity, pressure, tilt), and touch as clicks and drags at the exact positions.

### Headless `t2m run` vs the app (2026‑09‑26, idle, same configuration)

| | Resident memory | CPU |
|---|---|---|
| `t2m run` (no menu bar, no SwiftUI) | **28.7 MB** | 0 % |
| Tab2Mac.app `--background` | 61.7 MB | 0.3 % |

Both do nothing while idle; the app's extra memory is AppKit/SwiftUI and the menu-bar item. Streaming costs the same in both (it's the same runtime).

### M3 — loopback streaming

`Tab2MacStreamingTests` streams a synthetic 640×400 HEVC source over real TCP on localhost, then decodes it with VideoToolbox. It checks handshake ordering, sequential frame IDs, keyframe requests, H.264 fallback and backpressure. End-to-end latency with the tablet is recorded once the Android receiver runs (M4).

## Method notes

- Repeat each benchmark at least 3 times, and report the median of the p50s and the worst p95.
- Keep the Mac on power, with Low Power Mode off, and close other capture tools (Zoom, OBS).
- The display must be animating, or ScreenCaptureKit correctly delivers almost nothing.
- For 120 Hz, confirm with `t2m displays` that the virtual display really runs at 120 Hz.

## Power gate (opt-in)

`scripts/check-power.sh` runs `t2m bench-power` and fails when a scenario's SoC power above the idle
baseline is more than 15 % (and 50 mW) worse than `docs/power-baseline.json`. It needs the signed
`mac/build` and real hardware, so it is not in `check-all.sh` or CI; run it for pipeline changes while
the user is present, and record a new baseline with `--update` only from a known-good build.
