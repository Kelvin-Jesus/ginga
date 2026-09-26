# Android receiver: guide for agents

The tablet side of Tab2Mac (Kotlin, Gradle, no AndroidX). Read the repository's `CLAUDE.md` first,
then this file, then `README.md` here for the details of each feature.

## Commands

```sh
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17        # no system Java on this Mac
./gradlew test                                      # every JVM unit test, golden vectors included (~20 s)
./gradlew test assembleDebug                        # what a change must pass
./gradlew :transport:testDebugUnitTest --rerun      # one module, forced
./gradlew test --rerun-tasks --no-build-cache       # to see compiler warnings again (there must be none)
./gradlew --stop                                    # when done
../scripts/docker-android.sh                        # the same in a linux/amd64 container (AAPT2 is x86_64-only)
../scripts/check-all.sh --android
```

`local.properties` (gitignored) holds `sdk.dir=/opt/homebrew/share/android-commandlinetools`.
Test results: `*/build/test-results/**/TEST-*.xml`; the golden-vector count is printed in
`protocol/build/test-results/test/TEST-dev.tab2mac.protocol.GoldenVectorTest.xml`.

## Modules

| Module | What | Tests |
|---|---|---|
| `:protocol` (pure JVM) | Framing, every message, `MessageCodec`, clock sync, `ByteArrayPool`, pairing and direct-link crypto | codec, decoder, golden vectors, crypto vectors |
| `:transport` | `LinkTransport` engine (reader/writer threads, `SendQueue`, backoff, liveness watchdog), `TcpTransport` (adb), `AccessoryTransport` + `UsbAccessories` (AOA), `WifiTransport` (TLS 1.3, pinning) | fake links, real loopback TCP and TLS |
| `:decoder` | `DecoderConfigPlanner` (pure), `VideoDecoder` (async MediaCodec into a Surface) | planner |
| `:renderer` | `VideoSurfaceLayout`, `LatestFramePresenter`, `CursorGeometry` | pure parts |
| `:input` | `InputMapper` (touch, S Pen), `HidKeyboard` + `KeyboardCapture` (hardware keyboard → HID) | mapping tables |
| `:discovery` | Bonjour (`NsdMacDiscovery`, `NsdMacResolver`), TXT parsing | TXT |
| `:app` | `Session` (pure state machine: handshake, pairing, pause, timers), `ReceiverController`, `DirectLinkFlow`, Keystore stores, activities | session, flow, status text, manifest |

Pure logic lives in plain classes with injected clocks and fakes, so it is unit-tested on the
JVM; Android glue stays thin. Keep it that way: new behaviour gets a pure core and a test.

## Invariants

- **The protocol is the contract.** `protocol/PROTOCOL.md` and `protocol/test-vectors/` belong to
  the Mac side and are generated there (`t2m protocol-vectors`). Never edit them from here: if the
  spec is wrong or unclear, report it with the section. `GoldenVectorTest` must pass with every
  committed vector, byte-exact for binary messages.
- **Power first.** No polling: blocking readers, deadline timers (`Session.nanosUntilNextTick`),
  broadcasts and callbacks. Nothing runs while idle. No per-frame allocation on the video path
  (pooled payloads, zero-copy views, `AutoCloseable` owners); none per input or cursor message
  beyond the message object itself.
- **Latest frame wins.** Never queue decoded video; drop a stale backlog and ask for a keyframe.
  Same for cursor positions (one update per vsync).
- **Liveness is the transport's.** The watchdog thread (no I/O) tears a silent or write-blocked
  link down; nothing may depend on a blocked read returning.
- **Secrets are never logged**: loopback token, direct-link key, passphrases, pairing nonces.
  `toString()` of such types leaves them out.
- **Threads.** The session and controller run on `t2m-session`; input and key sends are
  thread-safe; UI state goes through `ReceiverController.state`.

## Do / don't

- Do run `./gradlew test assembleDebug` before saying something is done, with no warnings.
- Do add a test for every protocol change (codec + golden vector) and every state-machine change.
- Do use `TransportLog`/`AppLog` (`event key=value`), tags `T2M/<module>`.
- Don't add AndroidX or other dependencies without a reason worth its size.
- Don't touch `mac/`, `protocol/` or `config/` (report instead), and don't commit unless asked.
- Don't change tablet system settings, grant permissions from the shell, or enter the PIN.

## Device

- Galaxy Tab S11 (SM-X730, Android 16) on adb serial `R52Y80EE15V`; Android SDK platform-tools in
  `/opt/homebrew/share/android-commandlinetools/platform-tools`.
- It locks quickly behind a PIN. Check with `adb shell dumpsys window | grep isKeyguardShowing`;
  if it is locked, ask the user to unlock it. Never wake it with key events to get past the lock,
  and never enter the PIN.
- `adb install -r app/build/outputs/apk/debug/app-debug.apk` only when the user or coordinator
  said the tablet is free (not while someone is streaming or measuring).
- Logs: `adb logcat -s 'T2M/app:*' 'T2M/session:*' 'T2M/transport:*' 'T2M/decoder:*'`.
- Debug builds take scripted commands (see `MainActivity.handleAutomation`): `--ez connect true`,
  `--ez disconnect true`, `--ez directTest true [--ez directHotspot true]`, `--ez directCancel true`.
- Measure energy off the charger: on AC at its charge limit the battery current means nothing.
