# Roadmap and TODO

Ordered by value for the reference setup (Mac + Tab S11 over a Thunderbolt/USB‑C cable). Status of what exists: [status.md](status.md).

## Next

- [ ] **Verify on the device:** keyboard cover (KEY), scroll inertia, touch "gestures" mode, the no-router mode end to end (latency/fps vs normal Wi‑Fi, return to the previous network, tablet energy).
- [ ] **Other devices:** try the Tab S9 FE+ (90 Hz LCD, Exynos 1380) and the S25 Ultra (phone, 3120×1440) on every link; record them in status.md and performance.md.
- [ ] **Headless footprint:** measure `ginga run` against the app (memory, CPU, energy) and document.
- [ ] **Idle refinement:** after sustained motion stops, re-encode the last frame once at higher quality. Measure the visual gain before shipping (it costs one encode per stop).

## Later

- [ ] **Wi‑Fi Aware (NAN)** when Apple ships `WiFiAware` on macOS: a `WiFiAwareByteTransport` (publish on the tablet, subscribe on the Mac, `WAConnection` → the same TLS + pinning). Removes the Mac's network switch in the no-router mode (ADR‑25).
- [ ] **M8 Wi‑Fi UDP profile:** fragments ≤ 1200 bytes, Reed–Solomon FEC, NACK, LTR/IDR recovery, AES‑GCM from the TLS exporter. Only matters on lossy Wi‑Fi.
- [ ] **Packaging:** Developer ID signing and notarization (needs the user's Apple Developer account); the persistent-content-capture entitlement.
- [ ] **Multiple tablets** at once (one display each).
- [ ] **Pinch-to-zoom:** no public API to post a magnify gesture; revisit if one appears.

## TODO: Linux hosts

Ginga is macOS-only today. A Linux host needs the same five layers with Linux pieces; the protocol, the tablet app and the golden vectors stay as they are.

| Layer | macOS today | Linux plan |
|---|---|---|
| Virtual display | `CGVirtualDisplay` (private) | X11: `xrandr --setmonitor` on a dummy/virtual output (e.g. the `evdi` kernel module, as DisplayLink uses, or `xf86-video-dummy`); Wayland: compositor-specific (GNOME Mutter `RecordVirtual` via the ScreenCast portal with a virtual monitor, KDE KWin virtual outputs, wlroots `create_output` in Sway) |
| Capture | ScreenCaptureKit | PipeWire ScreenCast (xdg-desktop-portal) with DMA-BUF, zero-copy |
| Encode | VideoToolbox HEVC | VA-API (Intel/AMD) or NVENC (NVIDIA) through GStreamer or FFmpeg; HEVC or H.264 low latency |
| Transport | Network.framework, IOUSBHost | sockets + OpenSSL/rustls TLS; libusb for AOA (the handshake is the same control requests); adb reverse unchanged; Avahi for Bonjour |
| Input | CGEvent | `uinput` virtual pointer, tablet (`ABS_PRESSURE`, `ABS_TILT_*`, `BTN_TOOL_PEN`) and keyboard devices |
| No router | CoreWLAN + CoreBluetooth | NetworkManager (D-Bus) to join and restore; BlueZ (D-Bus) GATT client |

Suggested approach: a separate host implementation (Rust or C++ with GStreamer) that passes the golden vectors, rather than porting the Swift code; start with X11 + evdi + VA-API, then the Wayland portals. Container builds (`docker/`) can host its CI.
