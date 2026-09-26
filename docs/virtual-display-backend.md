# The virtual display backend boundary

The virtual display is the most platform-specific and least stable part of Tab2Mac. macOS has no public API for it (see [research §1](research.md#1-virtual-displays-on-macos)), so it rests on a private CoreGraphics API. This document covers:

- how that dependency is contained;
- what was verified, and on which macOS builds;
- what to do when Apple changes something.

## Containment rules

1. **One file touches the private API**: `mac/Sources/CGVirtualDisplayShim/T2MPrivateVirtualDisplay.m`. Nothing else may mention `CGVirtualDisplay*`. `grep -r CGVirtualDisplay mac/Sources` should only find the shim, comments, and the backend's type names.
2. **No link-time dependency.**
   - The classes are resolved with `NSClassFromString` and messaged through protocol-typed references.
   - The binary never references `_OBJC_CLASS_$_CGVirtualDisplay*`, so it still loads if Apple removes them.
3. **Verify before the first message.** `T2MPrivateAPIChecker` checks every class and selector the shim uses, *including the normalized Objective‑C type encoding* (for example `initWithWidth:height:refreshRate:` must be `@@:IId`).
   - If a signature changes, the backend reports "unavailable" instead of calling a function with the wrong ABI.
   - Alternative spellings (`setSerialNumber:`/`setSerialNum:`, `setQueue:`/`setDispatchQueue:`) are accepted.
   - Colour primaries are optional.
4. **No crash paths.** Every private call runs inside `@try/@catch`. Exceptions, nil objects, a display ID of 0, and `applySettings:` returning NO all become `NSError`, then `VirtualDisplayBackendError`, then `VirtualDisplayError`.
5. **The rest of the app depends only on `VirtualDisplayBackend`.** Only the composition roots (`Tab2MacApp/AppDelegate.swift`, `t2m`) construct `CGVirtualDisplayBackend`.
6. **Everything public stays public.** Mode selection, arrangement, mirroring and change monitoring use documented CoreGraphics APIs in `VirtualDisplayProvider`, not the private API.

## What the shim does

| Operation | Private calls |
|---|---|
| Create | `[[CGVirtualDisplayDescriptor alloc] init]`, then set name, max pixels, size in mm, vendor/product/serial, queue (main), termination handler, sRGB primaries. Then `[[CGVirtualDisplay alloc] initWithDescriptor:]`, then `displayID` |
| Advertise modes | `[[CGVirtualDisplayMode alloc] initWithWidth:height:refreshRate:]` for each mode, `[[CGVirtualDisplaySettings alloc] init]`, `setHiDPI:`, `setModes:`, then `-[CGVirtualDisplay applySettings:]` |
| Destroy | Release the `CGVirtualDisplay` (its `dealloc` removes the display) |
| System termination | The descriptor's termination handler, forwarded on the main queue |

**Values Tab2Mac passes:**

- **Identity:** vendor `0x5022` ("TAB" as a packed EDID manufacturer ID; macOS has no override for it), product `0x5311` (Tab S11) or `0x5312` (Ultra), and serial from configuration.
  - The identity must stay stable: macOS keys arrangement, mode memory and a permanent ColorSync profile to it.
- **Max pixels:** a square of (largest advertised logical dimension × 2 for HiDPI), for example 3200×3200 for the Tab S11 options. Square so that portrait can be applied live.
- **Size in mm:** from the panel's diagonal and aspect ratio (Tab S11: 236.9 × 148.1 mm, 274 ppi), swapped for portrait.
- **Modes:** the logical "looks like" sizes (points), preferred first, at the configured refresh rate, plus 60 Hz fall-backs.

## Verified behaviour

| macOS | Build | Hardware | Result |
|---|---|---|---|
| 26.6.2 | 25G83 | Mac16,1 (M4) | All requirements satisfied (`t2m probe`); the M1 verifier passes every structural check (create, own ID, extended desktop, NSScreen, System Information, target mode, window move, live mode + orientation change, removal) |

**Observed on 26.6.2** (details in research §1.2):

- `hiDPI=1` means mode sizes are points rendered at 2×.
- 120 Hz modes work.
- The `rotation` setting is ignored, so portrait is done with a swapped mode set.
- Creation to online: about 90–660 ms; a live re-mode takes about 350 ms; removal about 355 ms.
- **Other monitors can change mode** when the display appears. macOS keeps one configuration per set of displays, and while a HiDPI virtual display exists, an HDMI monitor's scaled HiDPI modes may be unavailable (measured: 2048×864 @2x 60 Hz became 2560×1080 100 Hz). Those choices belong to the user and persist per set, so the provider only reports them (`display.other-mode-changed`) and never changes another monitor's mode.

**Not yet tested:** macOS 14.x, 15.x, 27.x.

## When a macOS update breaks it

1. Run `t2m probe`, or the canary test: `scripts/test.sh --filter PrivateAPIChecker`. The report names the missing selector or the changed signature.
2. `t2m probe` also prints the full runtime interface, so you can compare it with the table in research §1.2.
3. If only a name moved, add the alternative spelling to `kRequirements` and the call site (the pattern already used for `setSerialNum:`).
4. If semantics changed, adapt the shim and extend the Objective‑C fakes in `mac/Tests/ShimFakes`, so the new behaviour is covered by tests without WindowServer.
5. Record the build in the table above.

## Replacing the backend

If Apple ships a public API (Path B), add a new target implementing `VirtualDisplayBackend`, then select it in the composition roots, for example based on `availability()`. No other module changes. The same applies to experimental backends; the only fully public fallback is a hardware dummy display plug, which needs no backend at all because capture only needs a `CGDirectDisplayID`.
