# Known issues and lessons

Problems that cost real time, what caused them, and the rule that came out of each. Add to it when something surprises you. Open issues come first.

## Open

| Issue | Workaround / plan |
|---|---|
| Wi‑Fi Aware (NAN) is iOS/iPadOS 26 only: `WiFiAware.framework` ships in the macOS 26 SDK with every symbol `@available(macOS, unavailable)` | The no-router mode uses the tablet's own network + CoreWLAN (ADR‑25) |
| `NSCursor.currentSystem` is marked "to be deprecated" | Only way to read the global pointer image; without it the pointer stays in the video |
| adb's relay delivers frames in bursts: ~1.7 % dropped at 120 Hz, RTT spikes of ~45 ms every ~4 s | Direct USB is the default (0 dropped) |
| Pinch-to-zoom can't be posted: no public magnify event | Not mapped |
| Debug builds of the tablet app are `run-as`-readable over adb (the loopback token is visible to someone who already has adb) | Release builds aren't |

## Fixed (keep the rules)

| What happened | Cause | Rule |
|---|---|---|
| The user's HDMI monitor lost its mode after a test | WindowServer persists per-display-set configurations when the set changes; a `.forSession` mode change got saved | Never change another monitor's mode; only report changes |
| "60 Hz composes at 6–22 fps" | Test harness bug: `NSWindow(contentRect:screen:)` is screen-relative, the load window landed elsewhere | Place windows by global frame |
| Core Animation ran the test pattern at 60 fps on a 120 Hz display | No `preferredFrameRateRange` | Ask for more than any display offers (240) |
| 156 IDRs in 39 s | VideoToolbox reads `MaxKeyFrameInterval = 0` as its default GOP | Huge values; a test pins it |
| One frame in 120 skipped at 120 Hz | `FrameCadence` re-anchored on a late timestamp | Pass through when the stream rate ≥ the display's |
| Paired tablets never listed; "Forget" impossible | File-based keychain returns `errSecParam` for `kSecReturnData` + `kSecMatchLimitAll` | List attributes, then read each item |
| A new Wi‑Fi identity at every launch (tablets had to re-pair) | The keychain labels certificates with their subject and ignores the label given at add | Find the certificate from the labelled key (public-key hash) |
| A reconnecting tablet got a display that was being removed | Display operations interleaved at awaits | Serialize display operations (ADR‑18) |
| Stale session forever after the Mac quit or the tablet app died on AOA | An accessory link reports neither | Liveness both sides; HELLO on a live link restarts; GOODBYE on quit (ADR‑23) |
| No-router mode "connected but didn't go back": the Mac stayed offline until the user picked a network, then got knocked off it again | A synchronous `scanForNetworks` (28 s) competed with macOS auto-join, whose association timed out; the fallback then cycled the radio under the network the user had just chosen | Leave, then wait for auto-join; never scan meanwhile; cycle the radio only when on no network (`NetworkRestore`); CoreWLAN calls off Swift's shared threads |
| The pointer vanished on the tablet after its app restarted on a live link | The Mac kept "shapes already sent" across a HELLO restart; the tablet had forgotten them, so it had no image for the arrow (and the capture leaves the pointer out) | Per-session state is reset in `endSession`; a new session gets the shapes and the current position again |
| The pointer on the tablet showed the wrong image (an I-beam over the desktop) or seemed to vanish | The image was read with the move event, before the app under the pointer set its own; a jump (a tap) has no later move to correct it | Read it again 100 ms and 400 ms after the pointer stops (`CursorTracker`) |
| The tablet's pointer vanished whenever it moved and showed only where it had stopped after a tap, whatever moved it (Mac mouse, finger, S Pen) | The video's SurfaceView sits below the window, so the window hands the compositor a transparent-region hint; it is recomputed only on layout passes, and moving the pointer by `translationX/Y` isn't one. The pointer kept landing in an area still marked transparent and was skipped (screenshots and screen recordings showed it; logs said visible) | Request a layout when the pointer's position changes (`CursorLayer`); any view that moves over the video by translation needs the same |
| The pointer didn't follow the Book Cover touchpad | Android reports touchpad pointer events as source mouse with tool type **finger**; they went out as touch hovers, which the Mac ignores | Source mouse ⇒ tool mouse; two-finger swipes (classification 3) become a two-finger touch (scroll); pinches and 3/4-finger swipes are dropped |
| Video frozen for 35 s, the tablet asking for a keyframe every 500 ms | After `vendor.mtk.vdec…error-code = 2` the MediaTek decoder kept every input buffer and never called `onError`; keyframes queued behind it | Restart the codec when it holds all input buffers for 1 s while frames arrive (`VideoDecoder.isStalled`) |
| A new accessory link started with bytes of the previous one ("bad magic") | Partial write in flight when the old link closed | The tablet resyncs until its first valid frame |
| Pointer tests "passed" with 0 frames | The harness's CGEvents were dropped (no Accessibility for the terminal) | Move the pointer through the tablet |
| Keychain/codesign prompts blocked unattended builds | Imported key without partition list | `build-app.sh` times out and falls back to ad-hoc (don't run it unattended) |
| The Android container build failed on Apple Silicon ("AAPT2 … Daemon startup failed") | Google ships AAPT2 and build-tools for Linux x86_64 only; the container was arm64 | The image is `linux/amd64` (Rosetta) |
| Tests couldn't find `Testing` | Command Line Tools only | `scripts/test.sh` |
| zsh `log: too many arguments` | zsh builtin | `/usr/bin/log` |
| A MITM could steer the 6-digit pairing code | No nonces | Commit–reveal (ADR‑20) |
| Any USB gadget in accessory mode got the screen and input | No approval check for accessory-mode devices | Approved serials only |
| Any local process (or tablet app) could take the screen over adb | Loopback trusted everyone | Loopback token (ADR‑21) |
