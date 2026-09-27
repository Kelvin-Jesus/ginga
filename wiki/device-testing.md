# Device testing

Tested so far: Galaxy Tab S11 (the reference, SM-X730), Galaxy S25 Ultra (phone, SM-S938B) and a Xiaomi phone (1220×2712 @120 Hz over direct USB). Status per feature is in `docs/status.md`.

## The devices

- **They are someone's daily devices.** Ask before anything that changes them; never enter a PIN, never change their settings or permissions. Tablets lock quickly with a PIN: ask to unlock and batch the tests while it's awake.
- **Don't inject input while the maintainer is using the device as a display.** `adb shell input` on a tablet that shows a live Mac desktop clicks and drags in whatever window is under it. Prefer `screencap`, logs and reports; inject only when agreed, in the stream view, on a quiet desktop.
- Always address a device explicitly (`adb -s <serial>`): the emulator, a tablet and phones are often attached together.

## Links and adb

- **Direct USB (AOA) is the default link.** In accessory mode the device re-enumerates (Google's `18d1:2d01`) and, depending on the phone, **adb can disappear** from `adb devices`. To reach adb again you'd have to turn direct USB off; usually it's simpler to update or check from the device itself.
- USB via adb needs the loopback token (`adb reverse`), which the Mac hands over itself.
- Wi‑Fi diagnosis: `/usr/bin/log show --predicate 'process == "airportd"'` and grep `DISASSOC|ASSOC request received from pid|SET POWER|Completed scan for pid|Auto-join association`: it names which process did what (SSIDs are redacted). Never switch the Mac's Wi‑Fi yourself (CLAUDE.md).

## Moving the Mac pointer in tests

The harness terminal can't post CGEvents, so move the pointer through the tablet: `adb shell input tap/swipe`, or `input stylus swipe` in the stream view (Ginga injects with its own grant). `input` can't hover a stylus or use two fingers; those stay manual (🧪 in status.md).

## Updating the apps on a device

- Devices run the **release-signed** APK. Android refuses an update signed with another key: install the release APK (`adb install -r`, keeps the app's data) or update from the device via the latest GitHub release. A debug build would need an uninstall first, which wipes the app's data and breaks the next release update too. Details in [releases](releases.md).
- The Mac app on the maintainer's machine runs from `mac/build/Ginga.app` ([dev environment](dev-environment.md) for rebuild and relaunch).

## Emulator

`s1avd` (Pixel 6 profile, 411×914dp) is set up for phone layouts; resize it (`adb shell wm size 1600x2560` + density 320) for a tablet-size check, and restore it afterwards. Compare tablet screenshots before/after a UI change: the tablet layout must stay pixel-identical unless the change is meant for it.
