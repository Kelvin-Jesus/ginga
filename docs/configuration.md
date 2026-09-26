# Configuration reference

Tab2Mac reads `~/Library/Application Support/Tab2Mac/config.json`, and the control panel writes it. A file passed with `--config PATH` (app, or `t2m … --config PATH`) applies to that run only: the control panel's changes then last until quit and are saved nowhere.

Every section and key is optional. A missing key takes the default below, so a file only needs what it changes, and old files keep working. Examples are in [`config/examples/`](../config/examples); the test suite decodes and validates each one.

```json
{
  "version": 1,
  "display": { "profile": "galaxy-tab-s11", "refreshRate": 120 },
  "power": { "batteryRefreshRate": 60 },
  "streaming": { "encoderPower": "automatic" }
}
```

`version` is the file format, currently 1. A newer version is rejected with a clear error rather than half-read.

**Invalid files are never overwritten.** If `config.json` can't be read (a typo, a value out of range, a newer version), Tab2Mac says so and runs with the defaults. The first change you save keeps the old file next to the new one as `config.unreadable-<date>.json`, so nothing you wrote is lost. Out-of-range values are named by their key, e.g. `streaming.bitrateKbps: 0 is outside 1000...200000`.

## `display` — the virtual display

| Key | Default | Meaning |
|---|---|---|
| `profile` | `galaxy-tab-s11` | Device preset that supplies every other `display` default. Values: `galaxy-tab-s11`, `galaxy-tab-s11-ultra`, `generic-1920x1200` |
| `name` | from profile | Name shown in System Settings › Displays |
| `identity` | from profile | `{ "vendorID", "productID", "serialNumber" }`. macOS remembers arrangement and mode per identity. Vendor 0x5022 is Tab2Mac's |
| `panel` | from profile | `{ "nativePixels": {w,h}, "physicalSize": {"widthMillimeters","heightMillimeters"}, "maxRefreshRate" }`. The physical size sets the reported DPI |
| `resolution` | profile default, 1280×800 for the Tab S11 | "Looks like" size in points, landscape |
| `extraResolutions` | profile options | Additional sizes offered in System Settings. The largest one sets the display's pixel budget |
| `hiDPI` | `true` | 2× backing (Retina). With `false`, one pixel per point |
| `refreshRate` | **`60`** | 60 or 120 (the profile's panel maximum). The stream runs at this rate unless `capture.maxFrameRate` caps it. At 120 Hz, see `power.batteryRefreshRate` |
| `orientation` | `landscape` | `landscape` or `portrait`. The tablet can also request it when it rotates |
| `arrangement` | `{ "placement": "automatic", "alignment": "start" }` | `placement`: `automatic` (macOS remembers), `left`, `right`, `above` or `below` the main display. `alignment` along the shared edge: `start`, `center` or `end` |

## `capture` — ScreenCaptureKit

| Key | Default | Meaning |
|---|---|---|
| `pixelFormat` | `420v` | `420v`, `420f` or `BGRA`. `420v` goes straight into the encoder; BGRA measured about twice the power |
| `showsCursor` | `true` | Draw the Mac's cursor into the stream |
| `limitToPanelResolution` | `true` | Downscale "more space" modes to the tablet's native pixels instead of sending more |
| `queueDepth` | `5` | ScreenCaptureKit surface pool, 3–8 |
| `frameIntervalHeadroom` | `2` | Capture asks for frames at up to `refresh × headroom`, so jitter never costs a frame |
| `maxFrameRate` | `null` | Optional cap on the stream below the display's rate (e.g. for a slow link), 1–240. `null` streams at the display's rate |
| `decimation` | `in-process` | When a cap applies: `in-process` picks frames on a fixed cadence from capture timestamps (exact); `capture-service` lets ScreenCaptureKit drop them (cheaper, but irregular: 51 fps with 33 ms gaps measured at 120 → 60) |

## `streaming` — tablets and the encoder

| Key | Default | Meaning |
|---|---|---|
| `codec` | `hevc` | `hevc` or `h264`. It falls back to the other if the tablet can't decode it |
| `bitrateKbps` | `40000` | Bitrate cap on USB, 1000–200000. The encoder spends far less on typical desktop content. Wi‑Fi adapts between 2 and 30 Mbit/s instead |
| `encoderPower` | `automatic` | `automatic`: lowest latency on the power adapter, `MaximizePowerEfficiency` on battery (about −40 % encoder power, +6 ms). Or pin `lowest-latency` / `lowest-power` |
| `port` | `47800` | Loopback port the tablet reaches through `adb reverse` (not 0). The Wi‑Fi port is chosen by the system and advertised over Bonjour |
| `adbAutoReverse` | `true` | Keep `adb reverse` in place for every authorised tablet. Event-driven (`adb track-devices`) |
| `helloTimeoutSeconds` | `5` | TCP and Wi‑Fi connections that don't say HELLO in time are closed, 0.5–600. USB accessory links wait: the app starts only after the user answers Android's prompt |
| `displayLingerSeconds` | `15` | A display created because a tablet connected is removed this long after the last tablet leaves, 0–86400. `null` keeps it |
| `directUSB` | **`true`** | USB accessory mode (M6): no developer mode or adb, and the steadiest link (120 Hz with no dropped frames, where adb's relay drops about 1.7 %). Only tablets in `approvedUSBDevices` are ever switched, so this lists candidates and does nothing else until you approve one |
| `approvedUSBDevices` | `[]` | Serial numbers allowed to be switched to accessory mode, and the only devices in accessory mode that get a session. The control panel's "Use this tablet" adds them; "Forget" removes one and ends its session |
| `wifi` | `false` | Accept paired tablets over Wi‑Fi (M7): TLS 1.3, Bonjour `_tab2mac._tcp`, pairing by a 6-digit code. The no-router mode starts the listener for its session even when this is off |
| `matchTabletDisplay` | `true` | A display created because a tablet connected takes that device's panel: its profile if known (Tab S11, S11 Ultra, S9 FE+, S25 Ultra), otherwise the size, density and refresh rates it reports. The refresh rate is capped at the panel's, the stream at the decoder's. A display you created from the control panel uses `display` as configured |

## `power`

| Key | Default | Meaning |
|---|---|---|
| `batteryRefreshRate` | `60` | On battery, the display runs no faster than this (1–240). At `refreshRate: 120` that means 120 Hz on the power adapter and 60 Hz on battery, switched live on the same display. `null` keeps the configured rate on battery |

## `input`

| Key | Default | Meaning |
|---|---|---|
| `touch` | `pointer` | `pointer`: a finger taps, drags and long-presses like a mouse. `gestures`: like Sidecar, fingers only scroll (two fingers, with inertia) and the S Pen points and clicks |
| `commandKey` | `meta` | Which key of the tablet's keyboard is ⌘: `meta` (the ⊞/Samsung key, as macOS treats PC keyboards) or `control` (so Ctrl+C copies) |

## `diagnostics`

| Key | Default | Meaning |
|---|---|---|
| `overlayEnabled` | `true` | Statistics overlay on the debug preview |
| `sampleIntervalSeconds` | `1` | How often diagnostics refresh (0.25–60), and only while a window showing them is visible |

## Not in the file

Some state lives elsewhere, on purpose:

- **Screen Recording and Accessibility grants** live in macOS (TCC).
- **This Mac's Wi‑Fi identity** is the key and certificate labelled "Tab2Mac Wi-Fi identity" in the login keychain.
- **Paired tablets' pins** are generic-password items, service `dev.tab2mac.paired-tablet`, in the login keychain. Forget one in the control panel.
