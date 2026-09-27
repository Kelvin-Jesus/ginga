# Troubleshooting

Start with the two built-in diagnostics:

```sh
mac/build/ginga probe      # is the private virtual-display API usable on this macOS build?
mac/build/ginga displays   # what does CoreGraphics see right now?
/usr/bin/log stream --level debug --predicate 'subsystem == "dev.ginga"'
```

## Virtual display

**"Virtual display backend unavailable" / `ginga probe` says NOT USABLE**

A macOS update changed the private interface. The probe lists the missing class or selector, or an incompatible type encoding. See [virtual-display-backend.md](virtual-display-backend.md#when-a-macos-update-breaks-it). Nothing crashes; Ginga simply refuses to create the display.

**The display doesn't appear, or "timed out: display … did not come online"**

- Check whether another tool with the same identity is running (another Ginga instance, a leftover `ginga create`). macOS 26 can refuse a second display with the same vendor and product. List the processes with `pgrep -fl Ginga` and `pgrep -fl ginga`.
- Use a GUI session: WindowServer isn't available over SSH without a logged-in console user.

**The display appears but is mirrored, or not listed for capture**

macOS 26 can auto-mirror new displays. Ginga switches its display back to "extend" after creating it. If you choose mirroring yourself in System Settings, Ginga respects that (the log shows `display.reconfigured … mirrored=true`).

**Another monitor changed resolution when the tablet display appeared**

macOS remembers display modes *per combination of connected displays*. The first time the virtual display joins a combination, other monitors may fall back to their default mode. For example, an external HDMI monitor went from "looks like 2048×864" to 2560×1080 @100 Hz in testing. Set the preferred mode once, in System Settings › Displays, while the tablet display is present; macOS remembers it for that combination.

**Resolution changes by itself right after the display appears**

WindowServer may restore a mode it saved for this display identity. For 3 s after creating or reconfiguring, Ginga re-selects the configured mode (`display.mode-reasserted` in the log). After that, a change you make in System Settings is respected.

**Portrait doesn't rotate**

Portrait swaps the display's mode set, which is the expected behaviour: macOS 26.6 ignores the private rotation setting. Use Ginga's orientation control, not System Settings' Rotation menu, whose effect on virtual displays is untested.

**A file named `Galaxy Tab S11-….icc` appeared in `/Library/ColorSync/Profiles/Displays/`**

macOS creates one colour profile per display identity, just as for a physical monitor. Ginga keeps a stable identity, so this happens once, not on every launch. It is harmless; remove it with `sudo rm` if you uninstall.

**Windows piled onto the tablet display, then the app crashed or quit**

The display disappears with the process, and macOS moves its windows back to the remaining displays. Nothing persists.

## Capture

**"Needs Screen Recording permission" / capture step SKIPPED**

- Grant Screen Recording to **Ginga**: System Settings › Privacy & Security › Screen & System Audio Recording. Then quit and relaunch it.
- Commands started from a terminal need the *terminal app* to have the permission. Prefer `open … Ginga.app --args --self-test`.

**Permission granted, but after rebuilding it's gone again**

Ad-hoc signed builds get a new code hash every time. Run `mac/scripts/create-dev-signing-identity.sh` once and rebuild; or `tccutil reset ScreenCapture dev.ginga.Ginga` and grant again.

**"… is requesting to bypass the system private window picker" every month**

This is macOS 15+ policy for apps that capture without Apple's picker. It is expected. The only way around it is the `com.apple.developer.persistent-content-capture` entitlement, which Apple grants on request (planned for M9 packaging).

**"display N is not available to ScreenCaptureKit"**

- A brand-new display can take several seconds to appear in `SCShareableContent`; Ginga waits up to 15 s.
- If the display is mirrored, it is not capturable (see above).

**Capture stops when the Mac locks or the display sleeps (error −3808)**

This is expected. The session retries with backoff (0.5 s up to 5 s), and capture resumes after unlock.

**The refresh rate changes by itself**

At 120 Hz, "Use 60 Hz on battery" (on by default) switches the display to 60 Hz when the Mac runs on battery, and back on the power adapter. It keeps the same display: windows don't move, and the tablet gets a new keyframe. Turn it off, or set `"power": { "batteryRefreshRate": null }`, to stay at 120 Hz on battery.

**Should the display run at 60 or 120 Hz?**

The default is 60 Hz, and the stream matches the display's rate. At 120 Hz, WindowServer composes the display twice as often, and apps on it animate twice as often. For continuous animation that costs about 0.8 W more on the Mac, and the tablet decodes twice as many frames at a higher bitrate. Choose 120 Hz for maximum smoothness when both devices are on power. An earlier note here said 60 Hz virtual displays compose irregularly. That was a measurement bug (the test window landed on another display), fixed in `LoadGenerator`.

**Frame rate is low**

- ScreenCaptureKit only delivers frames when something changes. A static desktop shows about 0 fps with many "idle" frames; that is intended.
- For measurements, use `--benchmark-capture`, which animates the display.

**The debug preview shows a "hall of mirrors"**

The preview window was moved onto the virtual display, so it captures itself. Keep it on the MacBook screen.

**Protected video is black**

DRM content is excluded from screen capture by macOS.

## Tablet connection (USB)

**The tablet doesn't connect**

1. `adb devices -l` must show the tablet as `device`. If it says `unauthorized`, accept the prompt on the tablet.
2. In Ginga, turn on "Accept the tablet over USB", or run `mac/build/ginga serve --synthetic` to test with a pattern. It runs `adb reverse tcp:47800 tcp:47800` automatically; check with `adb reverse --list`.
3. Only one server can own port 47800. Stop other `ginga serve` or Ginga instances.
4. Log: `/usr/bin/log stream --predicate 'subsystem == "dev.ginga" AND (category == "streaming" OR category == "transport")'`.

**Direct USB (accessory mode) doesn't start**

1. `mac/build/ginga usb` must list the tablet with `AOA 1` or `AOA 2`. If it says `AOA unknown`, a cable or hub may be blocking vendor requests; plug the tablet in directly.
2. The tablet must be approved (Control Panel › Tablet › "Use this tablet"). Ginga never switches other devices. A device already in accessory mode that isn't approved gets no session (`usb.accessory-ignored reason=not-approved` in the log) but is listed, and approving it connects it right away, without replugging.
3. After the switch, the tablet appears as `18d1:2d00` or `18d1:2d01` (`ginga usb`). If Android's "Open Ginga…" prompt was dismissed, unplug and replug.
4. Samsung *Auto Blocker* can block USB accessory commands; turn it off.
5. Log: `/usr/bin/log stream --predicate 'subsystem == "dev.ginga" AND category == "usb"'`.

**Connected, but the tablet shows nothing**

The Mac streams only after capture runs. Without Screen Recording permission for Ginga, capture waits (`session.capture-permission-missing` in the log). `ginga serve --synthetic` needs no permission and isolates the problem.

**Touch or S Pen does nothing on the Mac**

Ginga needs the "Post Event" privilege. Use Control Panel › Tablet › "Touch & S Pen control: Grant…", then enable Ginga under System Settings › Privacy & Security › Accessibility. The log shows `input.permission-missing` until it is granted.

**The MacBook's battery drains faster while the tablet is plugged in**

Over USB‑C the Mac powers the tablet, so the tablet charges from the MacBook's battery (up to ~15 W, far more than Ginga's own pipeline, which measures in hundreds of mW). Options:

- Samsung Settings › Battery › Battery protection ("Protect battery", stops at 80–85 %). This cuts the draw to almost nothing once the tablet is charged.
- Plug the Mac into power while you use the tablet.
- Wi‑Fi (M7) avoids the charge path entirely.

For the same reason, the "battery current" in the tablet's diagnostics overlay is the net charging current while the cable is connected, not what the app consumes.

**The stream stutters or latency spikes while Ginga is in the background**

Ginga holds a latency-critical activity (no App Nap, no timer coalescing, no idle sleep) only while a tablet is streaming and its app is in the foreground. If spikes remain, check for a `stream.closed` / reconnect in the log. Also run the power benchmark (`ginga bench-power`) to see whether another process is saturating the GPU or the video encoder.

**At 120 Hz, how do I see whether frames are lost?**

The Mac logs one line per session when it ends, and one per second from the tablet:

- `stream.closed … sent=… skipped_rate=… skipped_backpressure=… pacer_dropped=…`: at the display's own rate `skipped_rate` stays 0. `skipped_backpressure` counts frames skipped because the link still held two encoded frames, and `pacer_dropped` counts frames replaced while the encoder was busy.
- `stream.report frames=… dropped=… e2e_p50_ms=…`: what the tablet rendered and dropped.

**The S Pen draws like a mouse (no pressure) in an app**

Ginga presents the S Pen as a pen tablet, the way Sidecar presents the Apple Pencil: proximity events, then tablet points with pressure and tilt, and an eraser pointer for the pen's eraser. Apps that support pen tablets (Photoshop, Affinity, Krita, Pixelmator…) use them. Apps that only read the mouse (most of macOS's own apps) see a mouse. Hovering moves the pointer without clicking; the side button right-clicks.

**The pointer on the tablet lags or has the wrong shape**

When the tablet app supports it, the pointer isn't part of the video: the Mac sends its position and shape separately (`stream.cursor-shape` in the log when a new shape goes out), and the tablet draws it on top. It then follows with the link's latency. If the shape can't be read on this Mac, the pointer stays in the video.

**The stream stops and comes back by itself**

Both sides watch for silence. The tablet PINGs every second; the Mac drops a receiver it hasn't heard from for 5 s (`stream.closed reason=…nothing from the receiver…`), and over direct USB offers a fresh link at once. Quitting Ginga tells the tablet (GOODBYE `shutdown`), and it reconnects when Ginga is back.

## Wi‑Fi (beta)

**The tablet doesn't find the Mac**

Both must be on the same network, and "Accept paired tablets over Wi‑Fi" must be on. macOS asks once for Local Network access; if it was denied, allow Ginga in System Settings › Privacy & Security › Local Network. The port changes every time Ginga starts listening, and the tablet looks it up again each time, so there is nothing to configure.

**Pairing ends by itself**

- The tablet left, declined, or 2 minutes passed: the Mac's prompt closes by itself.
- Another pairing prompt was already showing: the Mac shows one at a time and declines the second. Answer the first, then try again.
- The tablet's app predates the current pairing protocol (the log shows `the tablet confirmed before the codes could be compared`): update Ginga on the tablet.

**The codes differ**

Decline on both screens. Different codes mean the two devices don't see each other's certificates: something between them is relaying the connection.

**A tablet I forgot can still connect**

It can't stream: forgetting removes its pin and ends its session, and the next connection has to pair again. If the Mac forgot the tablet but the tablet still remembers the Mac, the tablet asks you to pair again.

## No router (direct connection)

**"this tablet has no direct-link key yet"**: connect the tablet once by USB or Wi‑Fi (with the current apps); the key goes over that session.

**"no tablet offering a direct connection nearby"**: start **Direct connection** on the tablet first, keep it within Bluetooth range, and allow Bluetooth for Ginga on both devices.

**"needs Location access"**: macOS only lets apps see and join Wi‑Fi networks with Location Services allowed for them: System Settings › Privacy & Security › Location Services › Ginga.

**The Mac didn't return to its network**: ending the direct connection first says GOODBYE to the tablet (which takes its network down), then leaves the tablet's network and **waits up to 15 s for macOS auto-join**, doing nothing meanwhile: a scan or association of Ginga's own competes with auto-join (on the device, one scan took 28 s and made auto-join's association time out). Only if the Mac is still on no network does it join the previous one from the last scan, and only if that fails too does it turn Wi‑Fi off and on. A network you pick in the Wi‑Fi menu meanwhile is kept, never dropped. `direct.restored outcome=previous|other|none seconds=…` in the log (`category == "direct-link"`) says how it ended; passwords are never logged.

**The tablet's network appears in Wi‑Fi › Known Networks**: macOS remembers networks joined through CoreWLAN. The name is fixed per tablet (`DIRECT-T2-xxxx`) and the password changes every session, and the network only exists during a session, so the entry is harmless; remove it in System Settings › Wi‑Fi if you like (Ginga never edits known networks).

## Keyboard

**The tablet's keyboard does nothing on the Mac**: the stream must be in front on the tablet, and Ginga needs Accessibility (like touch).

**Some keys type the wrong symbol**: keys go as physical positions (HID usages from the Linux scan code), and the Mac turns them into characters with *its* input source, as with any USB keyboard and as Sidecar does with an iPad's keyboard. Letters and digits always match; symbols match only when the Mac's input source is the layout printed on the keyboard. A Brazilian ABNT2 cover (it has a `Ç` key and a `/?` key next to right Shift) needs **Brazilian – ABNT2** (or **Brazilian**) on the Mac; a US cover, **U.S.** (or **U.S. International – PC**, where `'` `"` `` ` `` `~` `^` are dead keys). Add it in System Settings › Keyboard › Input Sources and switch with the input menu or 🌐/Fn; Ginga doesn't change input sources itself. Covers bought elsewhere (e.g. Latin American, with `Ñ` where US has `;`) used in "US mode" type like a US keyboard with a US layout on the Mac, with one exception handled for you: the extra ISO key left of Z types `\ |` (as on the tablet) instead of the `§ ±` U.S. Mac layouts give it.

**⌘ shortcuts**: by default the Samsung/⊞ key is ⌘ and Alt is ⌥. With *⌘ on the tablet's keyboard: Ctrl* in the panel, Ctrl acts as ⌘ (Ctrl+C copies), as on Windows.

## Settings

**"The settings file couldn't be used … Running with defaults."**

`config.json` has a mistake (the message names the key), or it comes from a newer Ginga. Fix it and relaunch, or change any setting in the control panel: the old file is kept as `config.unreadable-<date>.json` next to the new one, never overwritten. See [configuration.md](configuration.md).

## Build and test

**macOS asks for the keychain password on every build**

`codesign` needs permission to use the "Ginga Development" key. Clicking "Always Allow" is not always enough for keys imported with `security import`. Allow codesign once from Terminal; it prompts for your login password without echoing it:

```sh
read -s "KC?Login password: " && echo && security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "Ginga Development" -k "$KC" ~/Library/Keychains/login.keychain-db >/dev/null && unset KC
```

`scripts/build-app.sh` never waits forever. After `GINGA_SIGN_TIMEOUT` seconds (default 30) it falls back to ad-hoc signing, and that one build then lacks the Screen Recording grant.

**`no such module 'Testing'` or `Library not loaded: @rpath/lib_TestingInterop.dylib`**

Only the Command Line Tools are installed. Use `mac/scripts/test.sh`, which adds the swift-testing paths.

**`log: too many arguments`**

zsh's builtin `log` shadows the system tool. Use `/usr/bin/log`.
