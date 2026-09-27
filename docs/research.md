# Platform research: constraints and capabilities

Research done on 2026‑09‑25 for **Ginga**, a project that makes a Samsung Galaxy Tab S11 a true extended display for an Apple Silicon Mac. There are two kinds of evidence here:

- **Measured on the development Mac** — marked **[M]**. That machine is a **Mac16,1 (MacBook Pro 14″, M4, 16 GB)** on **macOS 26.6.2 (25G83)**. It has the Command Line Tools with the 26.5 SDK and Swift 6.3.3, but no Xcode. The target MacBook Air M4 has the same SoC and media engine.
- **From primary sources** — numbered `[n]`, listed at the end.

Anything unconfirmed is marked **(unconfirmed)**.

> macOS 27 shipped on 2026‑09‑14 [2]. Nothing in this project has been tested on it yet. The private-API canary test and `ginga probe` exist so a re-test takes minutes.

---

## 1. Virtual displays on macOS

### 1.1 Is there a supported (public) API? — **No**

- **SDK headers.** Across the macOS 26.5 SDK, no public header declares a way to create a display. The only headers that mention "VirtualDisplay" are the long-deprecated `IOHIDRegisterVirtualDisplay` family (cursor bounds, deprecated since 10.x/11) **[M]**.
- **Release notes and WWDC.** The macOS 27 release notes and the WWDC26 macOS guide add nothing display-related [3][4].
- **DriverKit.** Documented families: Audio, BlockStorageDevice, HID, MIDI, Networking, PCI, SCSIController, SCSIPeripherals, Serial, USB, USBSerial, and the new **VideoDriverKit** (DriverKit 27) [5][6].
  - VideoDriverKit replaces IOVideoFamily and DAL plug-ins for *camera and video-capture* devices. It does **not** create displays and does not produce a `CGDirectDisplayID`.
  - There is **no display, framebuffer or GPU DriverKit family**.
- **Conclusion (Path B):** no documented API can create a third-party display that appears in System Settings › Displays. This is the constraint the whole architecture is built around.

### 1.2 The private `CGVirtualDisplay` API (Path A)

CoreGraphics' `CoreGraphics.tbd` exports four Objective‑C classes, `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`, `CGVirtualDisplayMode` and `CGVirtualDisplaySettings`, plus the constant `CGVirtualDisplaySettingsRefreshDeadlineNone` (= 0.0). None of them has a header **[M]**.

They are what Chromium's display tests, DeskPad, BetterDisplay, OpenDisplay, SideScreen and, reportedly, commercial products use [7][9][10][12][25].

**Interface dumped from the Objective‑C runtime on 26.6.2 [M]** (full dump: `ginga probe`):

| Class | Members used by Ginga (normalized type encodings) | Also present |
|---|---|---|
| `CGVirtualDisplayDescriptor` | `init` `@@:` · `setName:` `v@:@` · `setMaxPixelsWide:`/`High:` `v@:I` · `setSizeInMillimeters:` `v@:{CGSize=dd}` · `setVendorID:`/`setProductID:` `v@:I` · `setSerialNumber:` (alias `setSerialNum:`) `v@:I` · `setQueue:` (alias `setDispatchQueue:`) `v@:@` · `setTerminationHandler:` `v@:@?` · `setRed/Green/BluePrimary:`, `setWhitePoint:` `v@:{CGPoint=dd}` | `displayInfo`, `setDisplayInfoValue:forKey:` |
| `CGVirtualDisplayMode` | `initWithWidth:height:refreshRate:` **`@@:IId`** (width/height are `uint32`, not `NSUInteger` as in community headers) | `initWithWidth:height:refreshRate:transferFunction:` (`uint32`) |
| `CGVirtualDisplaySettings` | `init`, `setModes:` `v@:@`, `setHiDPI:` `v@:I` | `rotation` (uint32), `refreshDeadline` (double), `isReference` (BOOL) |
| `CGVirtualDisplay` | `initWithDescriptor:` `@@:@`, `applySettings:` `B@:@`, `displayID` `I@:` | `rotation`, `modes`, `hiDPI`, and descriptor echoes |

**Behaviour measured with a throw-away spike and the production code [M]:**

- **Creation.** `-initWithDescriptor:` returns within 3–11 ms. The display is not online until `-applySettings:` runs, which takes 77–350 ms (up to about 660 ms for the first display in a process). The display then gets its own `CGDirectDisplayID` (8, 9, …, 18 across runs) and extends the desktop.
  - It appears in `CGGetOnlineDisplayList` and `CGGetActiveDisplayList`, as an `NSScreen`, and in System Information (the same data as System Settings › Displays), with "Rotation: Supported".
- **HiDPI semantics.** Mode sizes are **logical points**. With `hiDPI=1`, a 1280×800 mode is rendered at 2560×1600 pixels, which is pixel-exact for the Tab S11, provided `maxPixelsWide`/`High` allow 2×.
- **Generated modes.** WindowServer builds a whole ladder of scaled and 1× modes from the listed modes and the `maxPixels` ceiling: 26–55 modes in the tests.
  - The first listed mode becomes the default and gets the native flag (`ioFlags` 0x2000007).
  - A macOS-restored mode can override it right after creation [9], so the provider re-asserts the configured mode for a few seconds.
- **120 Hz.** Modes at 120 Hz are accepted and selected ("1280×800pt (2560×1600px) @120.00 Hz"). Capture sustains **117.7 fps** at 2560×1600.
- **60 Hz composes normally (correction).** An early measurement showed a 60 Hz display updating at only 6–22 fps, mostly SCK "idle" frames. That was a bug in the test harness, not a macOS limit. The load window was created with `NSWindow(contentRect:…, screen:)`, which interprets the rect relative to that screen, so the window landed on another display. With the window placed by its global frame, a 60 Hz display streams **60.0 fps** with a 16.7 ms p95 frame interval. For power, 60 Hz is therefore the default (architecture ADR‑14).
- **Mode switching.** The public `CGConfigureDisplayWithDisplayMode` / `CGCompleteDisplayConfiguration(.forSession)` switch modes on the virtual display in about 350 ms, keeping the same display ID.
- **Rotation.**
  - `CGVirtualDisplaySettings.rotation` has **no visible effect** for values 1, 90 and 270: `CGDisplayRotation` stays 0 and the bounds stay landscape.
  - **Portrait therefore works by re-applying settings with width and height swapped.** This works live (same display ID, about 370 ms), as long as `maxPixels` is square.
  - OpenDisplay does the same, and DeskPad's rotation PR remains open [9][13].
- **Removal.** Releasing the `CGVirtualDisplay` object removes the display in about 355 ms, and process exit removes it too. Windows move back to the remaining displays.
- **Run loop requirement.** Without AppKit event processing, `CGDisplayCopyAllDisplayModes` returns 0 modes and `NSScreen` never sees the display. Tools must run `NSApplication`'s event loop; `ginga` does.
- **Window test.** A window created on the built-in display (ID 1) and moved onto the virtual display ended up on that display, confirmed by both `NSWindow.screen` and WindowServer's `CGWindowList` bounds.

**Community and field reports to design for:**

- macOS 14+ returns nil unless `vendorID` ≠ 0 and the identity (vendor/product/serial) is unique [8]. Ginga uses vendor `0x5022` (the packed EDID code "TAB"), for which no macOS override exists **[M]**.
- On 26.x, a virtual display misclassified as a TV can be **auto-mirrored** and disappears from `SCShareableContent` [16]. The provider detects mirroring after creation and forces an extended desktop.
- **Every display identity leaves a root-owned ICC profile** in `/Library/ColorSync/Profiles/Displays/` [18][19]. Observed: `Galaxy Tab S11-7B6E…icc` **[M]**. Never mint a new identity per run.
- A second virtual display with the same vendor+product can be refused on 26.6 [18] (single source). The multi-tablet design will need distinct product IDs.
- Removal is asynchronous (up to about 2 s) [19].
- `CGDisplayStream` returns nil for virtual displays on 15.x and is obsoleted [14]. Use ScreenCaptureKit.
- The cursor is not drawn on virtual displays unless capture composites it (`showsCursor`) [15].
- **FB17797423:** after a virtual display reconnects, ScreenCaptureKit streams can capture the *wrong* display [20]. Streams must be recreated on every display change.
- macOS stores display modes **per combination of connected displays** **[M]**. When the virtual display first appeared next to the external HDMI monitor, macOS applied that monitor's default mode for the new combination (2560×1080 @100 Hz instead of the user's 4096×1728 HiDPI) and restored it when the virtual display left. Setting it once while the tablet display is present fixes it.

**How existing products do it:**

| Product | Approach |
|---|---|
| DisplayLink Manager | User-space app, no kext, up to 4 "virtual displays", requires Screen Recording [21] |
| Duet | Same pattern; needs Screen Recording [22] |
| Luna Display | Hardware dongle creates a real GPU display, then screen capture [23] |
| BetterDisplay, OpenDisplay, SideScreen (Android target), DeskPad | `CGVirtualDisplay` + ScreenCaptureKit (DeskPad: CGDisplayStream) [9][10][12][25] |
| Splashtop Wired XDisplay | Unsupported since macOS 10.15 [24] |

### 1.3 Paths considered

| Path | Verdict |
|---|---|
| **A — private `CGVirtualDisplay`** | **Selected.** It is the only path that yields a real display entry and `CGDirectDisplayID` without compromising security. Every call is isolated behind `VirtualDisplayBackend` and verified at runtime (see [virtual-display-backend.md](virtual-display-backend.md)). Not App Store compatible; distribute with Developer ID and notarization. |
| **B — supported API** | None exists (§1.1). The abstraction lets a public API replace Path A when one appears. |
| **C — kexts, SIP off, WindowServer patching** | Rejected for production. A hardware dummy plug (HDMI/USB‑C emulator) plus ScreenCaptureKit is the only fully public fallback. It uses a real GPU output and costs a port, so it is documented but not built. |

---

## 2. Capturing the virtual display (ScreenCaptureKit)

- **Selecting the display.** Find the `SCDisplay` by `displayID` in `SCShareableContent`. A new virtual display can take up to about 15 s to appear there [20], so poll. Then use `SCContentFilter(display:excludingWindows: [])`.
  - `SCDisplay.width`/`height` are **points**. Set `SCStreamConfiguration.width`/`height` in pixels, from `CGDisplayModeGetPixelWidth`/`Height`.
- **Defaults on 26.6 [M].**
  - `queueDepth` defaults to **8**, although the docs say 3.
  - `minimumFrameInterval` defaults to 1/60, and `pixelFormat` to `420v`.
  - **Reading the unset `colorMatrix` or `colorSpaceName` crashes (SIGSEGV) [M].** Only ever set them.
- **Pacing quirk.** Requesting exactly 1/60 s on a 60 Hz virtual display yields about 51 fps [30]. Ginga requests 1/(2×refresh).
- **Pixel format.** Use `420v` (NV12, BT.709 video range). The hardware encoder consumes it natively (BGRA costs about 2 ms more per frame [M]), and some Android decoders mishandle full range [12].
- **Frame delivery.**
  - Frames arrive **only when content changes**. `SCFrameStatus.idle` frames carry no buffer [29], so idle desktops cost almost nothing.
  - `displayTime` in the attachments is `mach_absolute_time`. Ticks are 24 MHz on Apple Silicon (timebase 125/3), not nanoseconds **[M]**.
- **Stops.** Streams stop with error −3808 on screen lock or sleep and must be restarted [32]. The session retries with backoff.
- **Legacy APIs.** `CGDisplayStream`, `CGDisplayCreateImage` and `CGWindowListCreateImage` are obsoleted in the macOS 15 SDK [33].
- **Screen Recording permission (TCC).**
  - Capturing anything, including our own virtual display, needs it. There is no framebuffer access through `CGVirtualDisplay` **[M]**: the runtime exposes no frame API, only RPC ports.
  - **Monthly re-confirmation.** Since macOS 15, apps that capture without `SCContentSharingPicker` get an "allow for one month" alert. It has been refreshed on use since 15.1, and is still observed on 26.x [33][34][35][37]. The `com.apple.developer.persistent-content-capture` entitlement, granted by Apple on request for VNC-style apps, suppresses it [39][40].
  - **Ad-hoc builds lose the grant on every rebuild**, because the designated requirement is the code hash [42]. Development builds should use a stable signing identity (`scripts/create-dev-signing-identity.sh`).
  - Command-line tools are attributed to their terminal app. This session's shell had **no** grant **[M]**, which is why the app bundle has headless `--self-test` and `--benchmark-capture` modes.

---

## 3. Hardware encoding (VideoToolbox on M4) — measured [M]

The research agent's benchmark fed synthetic text-like 420v IOSurfaces. Figures are single runs, so treat them as indicative.

| Mode | 1080p | 1440p | 1600p (Tab S11) | 2960×1848 (Ultra) |
|---|---|---|---|---|
| Low-latency H.264 (`EnableLowLatencyRateControl`) | 6.0 ms | 7.8 ms | 8.5–9.8 ms | — |
| Low-latency HEVC | 6.3 ms | 8.5 ms | 9.2–10 ms | — |
| **Normal HEVC, `AllowFrameReordering=false`, `RealTime=false`** | **3.5 ms** | — | **5.5 ms** | **7.1 ms** |

- **Normal-mode HEVC** sustains 120 fps at every tested size. Low-latency mode blocks at 1440p and above (about 110 fps ceiling at 1600p).
- **Low-latency pitfalls.** Its default QP cap drops 57–68% of frames on full-screen scrolling at 20–40 Mbps; `MaxAllowedFrameQP=51` fixes that. H.264 low-latency silently drops *all* frames beyond level 5.2 pixel rates, for example 2960×1848@120.
- **`RealTime=true` + accurate `ExpectedFrameRate`** makes the encoder pace itself: HEVC p90 rises to about 12 ms, H.264 p90 to 33–35 ms. Use `RealTime=false`, or `ExpectedFrameRate` ≥ 2× the actual rate.
- **Unsupported properties.** `MaxFrameDelayCount` returns −12900 (unsupported) in every mode. So do `PrioritizeEncodingSpeedOverQuality`/`ConstantBitRate` in low-latency mode, and `EnableLTR` in normal mode.
- **Live bitrate changes.** `AverageBitRate` can be changed on a live session and settles in about 0.5–1 s.
- **LTR.** Reliable for H.264 low-latency; HEVC LTR is unreliable (1 token in 180 frames).
- **4:4:4.** The M4 hardware encodes HEVC 4:4:4 and 4:2:2, but Android only added a Main 4:4:4 profile constant in API 37, and Dimensity support is unconfirmed. Stay 4:2:0 for now.

Sources: [1][2][3][4] in the agent report, VTCompressionProperties.h (26.5 SDK); benchmark sources are kept in the session scratchpad.

---

## 4. Android decode and render (Galaxy Tab S11)

- **Device.** Tab S11 (SM‑X730): 11″ 2560×1600 120 Hz Dynamic AMOLED 2X, MediaTek **Dimensity 9400+**, 12 GB RAM, Android 16 / One UI 8, **Wi‑Fi 6E** (not 7), USB 3.2 Gen 1, S Pen in the box (no Bluetooth). The Tab S11 Ultra is 14.6″ 2960×1848 with Wi‑Fi 7 [21][22].
- **No video input over USB‑C.** DisplayPort Alt Mode is output only (DeX), so the tablet can never be a hardware monitor (unconfirmed, absence of evidence). Samsung "Second Screen" is Windows/Miracast only [42][43].
- **Low-latency decoding.**
  - Set `KEY_LOW_LATENCY=1` (API 30), and prefer decoders that advertise `FEATURE_LowLatency` [7][9].
  - Moonlight also sets `vdec-lowlatency=1` for MediaTek, and `KEY_PRIORITY=0`; it avoids `KEY_OPERATING_RATE` on non-Qualcomm chips [10]. MediaTek `vendor.mtk.*` keys appear only in forks (unconfirmed).
- **Rendering.**
  - Use `SurfaceView`, not `TextureView`: it gets a hardware overlay [15].
  - Use async `MediaCodec` callbacks, and release the newest frame with `releaseOutputBuffer(i, System.nanoTime())` [8][11].
  - Call `Surface.setFrameRate(120, FIXED_SOURCE)` and use ADPF hint sessions (richer in API 36) [16][17][18].
- **Main risk: MediaTek decode latency.** Moonlight users report 20–30 ms on older Dimensity chips and 5–8 ms on Snapdragon [19][20]. There is no public Tab S11 number, so it must be measured on the device in M4.
- **Input.** `MotionEvent` exposes pressure, tilt, orientation, hover and `BUTTON_STYLUS_PRIMARY` [24]. Use `requestUnbufferedDispatch` to avoid vsync batching.

---

## 5. Transport

### 5.1 Wired

| Option | Findings | Verdict |
|---|---|---|
| **Android Open Accessory (AOA 2)** | See the details below this table. | **Primary wired transport**, gated by a throughput benchmark (M6) |
| **ADB `reverse`/`forward`** | Needs Developer options + USB debugging (Samsung Auto Blocker may block it). 1 MiB payloads, 8×16 KB USB requests in flight each way. scrcpy measures 35–70 ms end to end. **Don't bundle Google's prebuilt adb** (SDK licence §3.4); use the user's adb (Homebrew `android-platform-tools` is installed here **[M]**) [22]–[33] | **Fallback / development transport**: shares the TCP code path, so it's nearly free |
| **USB tethering (RNDIS/NCM)** | macOS 26.6 has CDC‑NCM/ECM/EEM drivers but **no RNDIS** **[M]**. Android defaults to RNDIS unless the OEM picks NCM (unknown for the Tab S11). It is manual, and routes the Mac's internet through the tablet [34]–[39] | Not planned (revisit only if the Tab S11 uses NCM) |
| USB‑C video input | Not available on the Tab S11 (§4) | Impossible |

**AOA details:**

- **Handshake.** Control requests 51/52/53 switch the device to `18D1:2D00`, or `2D01` with ADB.
- **No developer setup and no network prompts.** Used by Android Auto's desktop head unit, SuperDisplay and spacedesk.
- **Mac side.** It works from user space via IOUSBHost/IOUSBLib, with no DEXT and no root. No kernel driver claims Android's MTP/PTP interfaces.
- **Main risk.** The kernel's `f_accessory` reads host→device data **stop-and-wait, 16 KB per read**. A zero-length packet is needed after transfers that are an exact multiple of the packet size.
- **Unconfirmed.** Throughput (estimated 25–35 MB/s on USB 2, more on USB 3), and Samsung Auto Blocker's effect [1]–[21].

### 5.2 Wi‑Fi

- **Protocol choices in similar products.**
  - Moonlight/Sunshine: UDP/RTP with Reed–Solomon FEC (5–20%), a ≤10 ms reorder wait, and reference invalidation or IDR on loss.
  - Parsec (BUD): UDP + DTLS, advertising "7 ms added".
  - scrcpy: TCP [44]–[48].
- **Plan.** Ship TCP first (`TCP_NODELAY`, small send buffer, latest-frame-wins). Then move to UDP with FEC and LTR/IDR recovery.
- **Hardware.** The M4 Macs and the Tab S11 are both Wi‑Fi 6E, 2×2, 160 MHz. The development Mac is currently on an **802.11ac** network **[M]**, so 6 GHz benefits need a 6E router.
- **Android.** `WIFI_MODE_FULL_LOW_LATENCY` (API 29) applies only while the app is in the foreground with the screen on, and needs `WAKE_LOCK` [52][53].

### 5.3 Discovery

- **Mac advertises, Android discovers.** The Mac advertises Bonjour `_ginga._tcp` via `NWListener.service`. Android discovers with `NsdManager`: `registerServiceInfoCallback` (API 34) and `DiscoveryRequest` (API 35); no multicast lock needed on 14+ [55][56].
- **Mac permissions.** macOS Local Network privacy applies to non-sandboxed apps. They need `NSLocalNetworkUsageDescription` + `NSBonjourServices`, and a stable signing identity; the grant can't be reset [39][58].
- **Android permissions.** Android 17 (targetSdk 37) adds the runtime `ACCESS_LOCAL_NETWORK` permission, and advertising always needs it — hence the Mac advertises [57].

---

## 6. Input injection on macOS

- **Posting events.** `CGEventPost` needs the **Post Event** privilege (`CGPreflightPostEventAccess`/`CGRequestPostEventAccess`, 10.15+), which is separate from Accessibility. Set the local-events suppression interval to 0 [26][27][28].
- **Pen.** Mouse events with `kCGEventMouseSubtypeTabletPoint`, plus pressure, tilt X/Y and rotation, bracketed by tablet proximity events [26][29].
- **Scrolling.** `CGEventCreateScrollWheelEvent2` in pixel units, with `ScrollPhase`/`MomentumPhase`.
- **Magnify/rotate gestures.** No public API. The private fields are fragile and ignored by macOS 27 for some gestures [30][31].
- **Sidecar (UX reference).** Pencil = pointer; touch = two-finger scroll + edit gestures. macOS 27 extends touch [32].

---

## 7. Permissions, components and limitations (summary)

| Platform | Needed | When |
|---|---|---|
| macOS | Screen Recording (TCC). Monthly re-confirmation unless entitlement | M1 capture |
| macOS | Post Event privilege | M5 input |
| macOS | Local Network (Info.plist keys + prompt) | M7 Wi‑Fi |
| macOS | USB: no entitlement unless sandboxed; no DEXT/kext | M6 AOA |
| macOS | **No** kernel extensions, **no** SIP changes, **no** WindowServer patching | — |
| macOS | Distribution: Developer ID + notarization; **not** Mac App Store (private API) | release |
| Android | AOA: user accepts "Open Ginga for this accessory?" (can tick "always") | M6 |
| Android | ADB fallback: Developer options + USB debugging | M4 |
| Android | `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `WAKE_LOCK` (low-latency lock); `ACCESS_LOCAL_NETWORK` if targeting SDK 37 | M4/M7 |

**Limitations to state to users:**

- Protected content (DRM video) captures black.
- Nothing is captured at the lock screen.
- macOS shows its screen-recording indicator while streaming.
- The private API may break with any macOS update; the canary test and `ginga probe` detect this.

---

## Sources

Numbering follows the three research reports; duplicate numbers across topics refer to that topic's list.

**macOS display/capture:**

- [1] developer.apple.com/documentation/coregraphics
- [2] 9to5mac.com/2026/09/09/apple-confirms-macos-27-golden-gate-launch-date-september-14/
- [3] developer.apple.com/documentation/macos-release-notes/macos-27-release-notes
- [4] developer.apple.com/wwdc26/guides/macos/
- [5] developer.apple.com/documentation/bundleresources/driverkit
- [6] developer.apple.com/documentation/videodriverkit
- [7] github.com/chromium/chromium/blob/main/ui/display/mac/test/virtual_display_util_mac.mm
- [8] chromium commit 817aeca14e33
- [9] github.com/peetzweg/opendisplay (VirtualDisplay.swift, MacSender.swift, PR 126, issue 213)
- [10] github.com/Stengo/DeskPad
- [11] github.com/waydabber/BetterDisplay/discussions/4280
- [12] github.com/tranvuongquocdat/SideScreen
- [13] DeskPad PR 67
- [14] github.com/rophy/rustdesk/issues/26
- [15] DeskPad issue 33
- [16] OpenDisplay PR 126
- [18] github.com/Rydersel/Candela tools/vdrig
- [19] github.com/go-macos/virtualdisplay
- [20] developer.apple.com/forums/thread/786829
- [21] support.displaylink.com/knowledgebase/articles/1932214
- [22] duetdisplay.com help centre
- [23] astropad.com/luna-display-versus-duet-display
- [24] Splashtop Wired XDisplay App Store page
- [25] BetterDisplay issue 4405
- [29] WWDC22 session 10155
- [30] OpenDisplay MacSender.swift
- [32] BetterDisplay issue 5643
- [33] macOS 15 release notes
- [34] 9to5mac 2024/08/14 on the monthly prompt
- [35] macOS 15.1 release notes
- [37] BeyondTrust community on Tahoe prompts
- [39] developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture
- [40] developer.apple.com/forums/thread/765103
- [42] TN3127

**Transport** (see the transport report):

- source.android.com AOA/AOA2
- android_f_accessory.c (android16‑6.12)
- ADB zero_length_packet.md, delayed_ack.md
- developer.android.com USB accessory, NsdManager, WifiManager, local-network-permission
- TN3179
- Samsung Tab S11 spec pages
- Moonlight / Sunshine / Parsec documentation

**Codec/input** (see the codec report):

- WWDC21 10158
- VTCompressionProperties.h
- Chromium vt_video_encode_accelerator_mac.mm
- MediaFormat/MediaCodec reference
- Moonlight MediaCodecHelper.java and Game.java
- CGEvent headers
- Mac Mouse Fix TouchSimulator.m
- Apple Sidecar guide

## Wi‑Fi Aware (NAN) on the Mac (checked 2026‑09‑26)

- The macOS 26 SDK ships `WiFiAware.framework` (Swift module only), but every declaration carries `@available(macOS, unavailable)` (28 of them, plus `macCatalyst`/`tvOS`/`watchOS`/`visionOS` unavailable). The API (`WAPublishableService`, `WASubscribableService`, `WAConnection`, `WAPairedDevice`, `WASharedSecret`) is iOS/iPadOS 26.0+ only. Wi‑Fi Aware apps also need an entitlement and service declarations in Info.plist.
- The Galaxy Tab S11 supports it: `pm list features` shows `android.hardware.wifi.aware` (also `wifi.direct`, `bluetooth_le`).
- Consequence: the no-router mode uses the tablet's own network (Wi‑Fi Direct group) and CoreWLAN on the Mac (ADR‑25), and a Wi‑Fi Aware transport waits for macOS support.

