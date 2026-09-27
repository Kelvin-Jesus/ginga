# mac/: notes for agents

Swift 6.3, SwiftPM, macOS 14+ (developed on 26.6.2, M4). Start with the root `CLAUDE.md`.

## Build and test

- `scripts/test.sh` wraps `swift test` and adds the swift-testing framework paths the Command Line Tools don't. Plain `swift build --build-tests` fails with "no such module 'Testing'".
- Incremental builds occasionally miss a default argument that changed in another module ("Undefined symbols … __allocating_init"): `touch` the calling file.
- Hardware tests are opt-in: `GINGA_INTEGRATION=1 scripts/test.sh --filter RealVirtualDisplay` creates a real display.
- Keychain tests use a throwaway file-based keychain (`TemporaryKeychain`), never the login keychain.
- Timing tests use `eventually {}` with generous timeouts; don't shorten them to "make CI faster".

## Signing and permissions

- `scripts/build-app.sh` signs with the "Ginga Development" identity when present, so Screen Recording, Accessibility, Bluetooth and Location grants survive rebuilds. With ad-hoc signing every rebuild loses them.
- TCC is per responsible app: `ginga` started from a terminal uses the terminal's grants.

## Where things are

- Composition: `Sources/GingaRuntime/GingaRuntime.swift` (the only place that picks the display backend).
- Session lifecycle: `DisplaySession` serializes display operations (ADR‑18) and chains capture starts/stops.
- Receivers: `StreamServer` (pending set, one current receiver, leases, liveness), `StreamConnection` (one receiver).
- Protocol: `Sources/GingaProtocol` (messages, codec, `TestVectors.swift` generates `protocol/test-vectors`).
- Input: `Sources/InputInjection` (`InputInterpreter` pure; `CGEventInjector`; `KeyboardMapper` pure).
- UI (Ginga design system): `Sources/GingaApp/Design/` (`GingaTheme.swift` is generated from `design/ginga-design/tokens.json`: don't edit it by hand; components and the palette environment live next to it). Screens: `MainWindowView`, `SettingsView`, `Sheets`, `StatusItemController`; state in words in `AppModel+Presentation`. Every user-facing string goes through `tr("português", "English")`.
- Review the UI without touching the screen: `.build/debug/GingaApp --config <scratch.json> --render-ui <dir>` writes the main window and Ajustes in Claro, Escuro and Black espacial as PNGs and quits (starts nothing).
- The Command Line Tools have no SwiftUI macro plugins: no `@Entry`, `#Preview` or `@Previewable`; use `EnvironmentKey`.

## Log categories

`virtual-display`, `capture`, `session`, `encoder`, `streaming`, `transport`, `usb`, `security`, `input`, `direct-link`, `app`, `benchmark`. Messages are `event.name key=value`. Useful: `stream.report` (the tablet's view once a second), `stream.closed … skipped_* pacer_dropped cursor_messages`, `usb.accessory-*`, `adb.token-delivered`.
