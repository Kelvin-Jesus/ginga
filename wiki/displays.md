# Displays

## Never change another monitor's mode

Not even `.forSession`, not even in an experiment (CLAUDE.md "Never do"). On 2026‑09‑25 a test that set the maintainer's HDMI monitor mode "for the session" got **persisted**: when the display set changes (a virtual display added or removed), WindowServer saves the current configuration of the set being left into `/Library/Preferences/com.apple.windowserver.displays.plist` (`DisplayAnyUserSets`, one entry per set of display UUIDs). Their lid-closed "HDMI only" set went from 2048×864@2x 100 Hz to 2560×1080 60 Hz and couldn't be restored through public API (scaled HiDPI modes are only listed while current, `CGConfigureDisplayWithDisplayMode` returned 1000, `CGRestorePermanentDisplayConfiguration` did nothing). They had to re-pick it in System Settings.

- Product code only **reports** other displays' mode changes (`display.other-mode-changed`).
- Read-only tools are fine for experiments: `CGDisplayCopyDisplayMode` polling, `plutil -p` of that plist.
- Check `AppleClamshellState` before assuming the built-in panel is online: the Mac often runs lid-closed.

## HiDPI side effect

While a **HiDPI** virtual display exists, the M4 stops offering the external monitor's HiDPI scaled mode (its 4096×1728 backing), so macOS switches that monitor to native 2560×1080 @100 Hz. A 1× virtual display keeps it. Keep this in mind when choosing the virtual display's defaults and when a monitor "changes by itself".

## Naming

The virtual display is named after the device: its profile's name for known models (`DeviceProfile`, e.g. "Galaxy Tab S11"), otherwise the name the owner gave the device (HELLO `device.name`), otherwise its model. See `docs/virtual-display-backend.md` for the private API rules (CLAUDE.md invariant 5).
