# Power

The maintainer's words: the app must run "using the least battery possible and with the best possible performance on both sides". The yardstick is Sidecar, which uses very little. A smooth stream that drains the MacBook or the tablet is a failure (CLAUDE.md invariant 2).

## How to judge a change

- Decide defaults (display Hz, stream fps, where frames are decimated, pixel format, encoder hints) from **measured energy**, not intuition: `ginga bench-power`, `ginga energy`, `scripts/check-power.sh` (on real hardware; the first run with `--update` writes the baseline `docs/power-baseline.json`, which is not recorded yet).
- IOReport's "Energy Model" works without sudo (CPU, GPU, AVE encoder, VDEC, DRAM); `proc_pid_rusage` V6 gives `ri_energy_nj` for same-user processes. Don't use `powermetrics` (needs sudo).
- Report energy next to latency and fps in `docs/performance.md`.

## Rules that came from measurements

- **Nothing runs when nothing changes:** no polling timers (adb is watched with `adb track-devices`), capture only while a consumer exists, UI sampling only while a window shows it, pause when the tablet app is in the background, suspend a Web Audio context when its sound ends.
- **Match the display's Hz to the stream's fps** instead of decimating: ScreenCaptureKit's own dropping is lossy (120→60 gave 51 fps with 33 ms gaps).
- Measured 2026‑09‑26: 60 Hz→60 fps adds ~229 mW, the old default (120 Hz + SCK drops) ~408 mW; 120→120 costs ~0.8 W more than 60. Default is 60 Hz; at 120 Hz, `power.batteryRefreshRate` (60) switches live on battery. The adb relay costs ~2 mW; the Ginga process ~10 mW while streaming, 0 when paused.
- **120 Hz stability:** no periodic keyframes (VideoToolbox treats `MaxKeyFrameInterval = 0` as a ~30-frame GOP, so set huge values) and a FramePacer with at most 2 frames in flight: 0.06 % single-frame skips, 14 ms worst case.
- Android: zero-copy SurfaceView rendering, `Surface.setFrameRate` so a 120 Hz panel can drop to 60, no per-frame allocations, keep-screen-on only while streaming.
- UI animation (dithering, starfields) only while visible, at low frame rates (the Mac's galaxy runs at 12 fps, ~0.4 ms per frame), and off with reduced motion.
