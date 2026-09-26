# Status

What works, how it was verified, and what is left. Update it with every change that moves a line. Milestone definitions: [milestones.md](milestones.md). Plans: [roadmap.md](roadmap.md).

Legend: ✅ verified on the device · 🧪 unit/loopback-tested, not yet on the device · 📝 documented only.

## Mac ↔ Galaxy Tab S11 (SM-X730), verified 2026‑09‑26

| Area | State | Evidence |
|---|---|---|
| Virtual display (create, modes, orientation, arrangement, removal) | ✅ | `t2m verify`, M1 sign-off |
| Capture (420v, on demand, restart on reconfiguration) | ✅ | benchmarks in performance.md |
| HEVC encode (5.9 ms p50 at 2560×1600), keyframes on demand | ✅ | `t2m bench-encode` |
| USB via adb, with the loopback token | ✅ | 60 fps, 0 dropped; a tokenless local client is refused |
| **Direct USB (AOA), the default** | ✅ | 120 Hz: 120.2 fps, 0 dropped, e2e p50 ≈ 13 ms; approval required |
| Auto-reconnect: tablet app killed, Mac quit, app restarted on a live link | ✅ | liveness 5 s, GOODBYE `shutdown`, HELLO restart |
| Wi‑Fi (Bonjour, TLS 1.3, pinning, pairing with commitments) | ✅ | 60 fps, 0 dropped; stable Mac identity across launches |
| Touch (tap, drag, long press, two-finger scroll) | ✅ | exact positions |
| Scroll inertia after a flick | 🧪 | `adb input` can't do two fingers |
| Touch mode "gestures" (Sidecar-like) | 🧪 | |
| S Pen as a pen tablet (proximity, pressure, tilt, eraser) | ✅ | real pen: pressure 0–0.89, tilt −0.2…0.73 |
| Keyboard cover / hardware keyboard (KEY) | ✅ partly | Book Cover Keyboard Slim (EF-DX730) types on the Mac; a Latin American cover used as US matches the Mac's U.S. layouts key for key; the ISO key left of Z now types `\ |` like on the tablet (🧪 retest) |
| Pointer as a side channel (CURSOR) | ✅ | overlay at the exact position; capture without pointer. Fixed: shapes weren't resent after a HELLO restart (pointer invisible) — 🧪 retest |
| No-router mode (tablet network + BLE handover + CoreWLAN) | ✅ partly | 2026‑09‑26: BLE handover, join and TLS session on the tablet's network, 60 fps. The way back failed (a 28 s scan fought macOS auto-join); rewritten as `NetworkRestore` (8 unit tests) — 🧪 retest, then latency/fps vs normal Wi‑Fi and tablet energy |
| Other devices (Tab S9 FE+, S25 Ultra, any Android) | 🧪 | profiles + panel from HELLO + decoder cap; not tried on those devices |
| Headless `t2m run` | ✅ | idle: 28.7 MB vs 61.7 MB for the app, 0 % CPU |
| Energy (60 Hz default, pause, battery-aware encoder) | ✅ | performance.md |

## Not done

See [roadmap.md](roadmap.md): Wi‑Fi Aware (blocked: not on macOS 26), M8 UDP/FEC, idle refinement, Developer ID packaging, multiple tablets, Linux hosts, pinch-to-zoom (no public macOS API).
