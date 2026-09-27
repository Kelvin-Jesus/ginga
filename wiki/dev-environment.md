# Dev environment

The reference machine is an Apple Silicon MacBook Pro (M4) on macOS 26, often lid-closed with an external monitor. Commands are in CLAUDE.md; these are the traps.

## Mac toolchain

- **Command Line Tools only, no Xcode.** swift-testing needs `mac/scripts/test.sh` (it adds the CLT `Testing.framework` paths). CI runners have Xcode and run `swift test` directly.
- **No SwiftUI macros** with the CLT: no `@Entry`, `#Preview`, `@Previewable`. Use `EnvironmentKey`.
- **zsh's `log` builtin shadows the tool:** always `/usr/bin/log show --predicate 'subsystem == "dev.ginga"'` (add `--info` for info-level lines). Watch output filters: `swift build` ends with "Build of product 'x' complete!", not "Build complete".
- **Stale incremental builds.** SwiftPM can miss a changed default argument inlined into another module ("Undefined symbols … __allocating_init"): `touch` the calling file and rebuild.
- **Swift 6 isolation traps.** A closure created inside a `@MainActor` method and handed to a non-Sendable callback (`DispatchSource.setEventHandler`) is inferred main-actor isolated and traps when fired off the main thread: build such closures in `nonisolated static` helpers. A Swift 6.3 region-isolation compiler crash (signal 6 in SendNonSendable) went away the same way.
- **Intel slice.** `swift build --triple x86_64-apple-macosx14.0` works with the CLT; the tests run under Rosetta by calling `swiftpm-testing-helper` through `arch -x86_64` on the built bundle. Rosetta offers no hardware HEVC encoder, so encoder suites skip there.

## Signing and privacy permissions

- The app is signed with a self-signed "Ginga Development" identity so macOS keeps Screen Recording, Accessibility, Bluetooth and Location grants across rebuilds; ad-hoc signing loses them on every build.
- `mac/scripts/build-app.sh` can raise a keychain prompt. Unattended, it times out (`GINGA_SIGN_TIMEOUT`) and falls back to ad-hoc, which costs the grants. Only run it when the maintainer is around; `swift build -c release` checks compilation without touching the bundle.
- Relaunch the app gracefully: `osascript -e 'tell application id "dev.ginga.Ginga" to quit'`, then `open mac/build/Ginga.app` (GOODBYE reaches the tablet; it reconnects on its own).
- The harness's terminal has no Accessibility grant: CGEvents it posts are silently dropped. A listen-only CGEventTap still sees events (useful to check pen pressure).

## Android toolchain

- No system Java: Gradle needs `JAVA_HOME=/opt/homebrew/opt/openjdk@17`. SDK, build-tools and emulator live under `/opt/homebrew/share/android-commandlinetools`.
- The Docker build (`scripts/docker-android.sh`) must be `linux/amd64`: AAPT2 is x86_64-only and the arm64 image fails with "AAPT2 Daemon startup failed".
- Debug builds accept automation extras on MainActivity, e.g. `--es preview <state>` to draw any home state without a Mac and `--ez stream true` for the display screen (see `android/README.md`).

## Other tools

- Homebrew's ffmpeg can break after upgrades (missing `libx265`); Remotion ships a working ffmpeg in `video/node_modules/@remotion/compositor-darwin-arm64` (run with `DYLD_LIBRARY_PATH` set to that folder; it lacks `afade`/`alimiter`).
- Keep experiments and test configs in a scratch folder and launch with `--config <file>`: never write the maintainer's `config.json`.
