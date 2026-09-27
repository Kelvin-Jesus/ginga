# Status

What works, how it was verified, and what is left. Update it with every change that moves a line. Milestone definitions: [milestones.md](milestones.md). Plans: [roadmap.md](roadmap.md).

Legend: ✅ verified on the device · 🧪 unit/loopback-tested, not yet on the device · 📝 documented only.

## Mac ↔ Galaxy Tab S11 (SM-X730), verified 2026‑09‑26

| Area | State | Evidence |
|---|---|---|
| Virtual display (create, modes, orientation, arrangement, removal) | ✅ | `ginga verify`, M1 sign-off |
| Capture (420v, on demand, restart on reconfiguration) | ✅ | benchmarks in performance.md |
| HEVC encode (5.9 ms p50 at 2560×1600), keyframes on demand | ✅ | `ginga bench-encode` |
| USB via adb, with the loopback token | ✅ | 60 fps, 0 dropped; a tokenless local client is refused |
| **Direct USB (AOA), the default** | ✅ | 120 Hz: 120.2 fps, 0 dropped, e2e p50 ≈ 13 ms; approval required |
| Auto-reconnect: tablet app killed, Mac quit, app restarted on a live link | ✅ | liveness 5 s, GOODBYE `shutdown`, HELLO restart |
| Wi‑Fi (Bonjour, TLS 1.3, pinning, pairing with commitments) | ✅ | 60 fps, 0 dropped; stable Mac identity across launches |
| Touch (tap, drag, long press, two-finger scroll) | ✅ | exact positions |
| Scroll inertia after a flick | 🧪 | `adb input` can't do two fingers |
| Touch mode "gestures" (Sidecar-like) | 🧪 | |
| S Pen as a pen tablet (proximity, pressure, tilt, eraser) | ✅ | real pen: pressure 0–0.89, tilt −0.2…0.73 |
| Keyboard cover / hardware keyboard (KEY) | ✅ partly | Book Cover Keyboard Slim (EF-DX730) types on the Mac; a Latin American cover used as US matches the Mac's U.S. layouts key for key; the ISO key left of Z now types `\ |` like on the tablet (🧪 retest) |
| Pointer as a side channel (CURSOR) | ✅ | overlay at the exact position with the right image (arrow over the desktop, checked by screenshot); the image is read again after the pointer stops, and shapes are resent after a HELLO restart |
| Book Cover touchpad (mouse hover, clicks, two-finger scroll) | 🧪 | Android reports it as a mouse with a finger tool; now sent as a mouse (the Mac pointer follows), two-finger swipes scroll, Android's own arrow is hidden over the video. Needs a hand on the touchpad |
| Decoder stall recovery (MediaTek stops taking input after a stream error) | 🧪 | restart after 1 s without input; seen once on the device (35 s frozen video) |
| No-router mode (tablet network + BLE handover + CoreWLAN) | ✅ partly | 2026‑09‑26: BLE handover, join and TLS session on the tablet's network, 60 fps. The way back failed (a 28 s scan fought macOS auto-join); rewritten as `NetworkRestore` (8 unit tests) — 🧪 retest, then latency/fps vs normal Wi‑Fi and tablet energy |
| Other devices (Tab S9 FE+, S25 Ultra, any Android) | 🧪 | profiles + panel from HELLO + decoder cap; not tried on those devices |
| Headless `ginga run` | ✅ | idle: 28.7 MB vs 61.7 MB for the app, 0 % CPU |
| Energy (60 Hz default, pause, battery-aware encoder) | ✅ | performance.md |

## Ginga UI (design/ginga-design), 2026‑09‑26

| Area | State | Evidence |
|---|---|---|
| Name: Ginga everywhere (formerly Tab2Mac) | ✅ Mac, ✅ Android | app, modules, bundle id `dev.ginga.Ginga`, package `dev.ginga.receiver`, frame magic "GN", Bonjour/BLE/AOA identities; the Mac copies its settings from the former folder once |
| Themes Claro / Escuro / Black espacial / Sistema + Idioma (Português / English / Sistema) | ✅ Mac, ✅ Android | Mac `--render-ui`; Android emulator screenshots (the tablet's screen was off) |
| Android home by state, Ajustes, stream sky + toast | ✅ Android (🧪 Pareando/Conectado/stream screens on the device) | HomeModelTest, StarfieldMathTest; 322 Android tests |
| Main window, Ajustes, pairing sheet, Sem roteador sheet, menu bar by state | ✅ Mac (🧪 pairing sheet on the device) | renders; 380 Mac tests |
| Microinteractions: switch spark, press scale, orbit/pulse, pairing digits, row rise, comet | ✅ Mac | only while visible, off with reduced motion |
| Black espacial scenery: dithered galaxy (Mac main window, tablet home) and black hole (Mac pairing / Sem roteador, tablet stream waiting) | ✅ Mac, ✅ Android | ~0.4 ms/frame at 10 fps only while visible; still with reduced motion |
| Brand fonts (Unbounded, Figtree, IBM Plex Mono) | ✅ Mac, ✅ Android (🧪 on the device) | bundled under SIL OFL (`design/brand/fonts/`) |

## Distribution, 2026‑09‑27

| Item | State | Evidence |
|---|---|---|
| Tag → GitHub release (signed APK, universal Ginga.app, SHA256SUMS) | 📝 waits for the signing secrets | `.github/workflows/release.yml`; development.md › Releases |
| Android release signing from env / secrets, version from the tag | ✅ | local `assembleRelease` with a throwaway key: v2 signature, versionCode 200 for 0.2.0-beta.1 |
| Site (Astro, pt/en) on GitHub Pages | ✅ | `site/`, `.github/workflows/site.yml`; kelvin-jesus.github.io/ginga |
| Universal Mac app (arm64 + x86_64) | ✅ build, 🧪 Intel hardware | `lipo` shows both; 386 tests pass as x86_64 under Rosetta; x86_64 `ginga protocol-vectors` identical |

## Not done

See [roadmap.md](roadmap.md): Wi‑Fi Aware (blocked: not on macOS 26), M8 UDP/FEC, idle refinement, Developer ID packaging, multiple tablets, Linux hosts, pinch-to-zoom (no public macOS API).
