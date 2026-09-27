# Tab2Mac — Android receiver (the Ginga app)

The product is called **Ginga** on screen; Tab2Mac stays the internal name (package, classes,
logs, the USB accessory strings, the Bonjour type, the certificate subject, HELLO `app.name`).

Turns a Galaxy Tab S11 into an extended display of a Mac: receives the HEVC/H.264 stream,
decodes it straight into a `SurfaceView`, and sends touch and S Pen input back. The wire protocol
is [`protocol/PROTOCOL.md`](../protocol/PROTOCOL.md) (v1); the design is in
[`docs/architecture.md`](../docs/architecture.md) §2.6–2.7.

Milestones: **M4** (receiver over USB via `adb reverse`) is implemented and runs on the Tab S11.
The **M5** input path (touch, S Pen pressure/tilt/hover/buttons) is implemented on the tablet
side; the Mac's injection is the lead's side. **M6** (direct USB through Android Open Accessory,
no developer options) and **M7** (Wi‑Fi: discovery, mutual TLS 1.3, pairing, pinning) are
implemented and unit-tested; both still need a run on the tablet with someone there to accept
Android's prompt or compare the pairing code.

## Modules

| Module | Kind | Responsibility |
|---|---|---|
| `:protocol` | Kotlin/JVM | Framing (streaming `FrameDecoder`, 16 MiB limit), every v1 message (JSON via kotlinx-serialization, binary VIDEO_FRAME/INPUT/PING/PONG with `headerLength`/`recordLength` skipping), `ClockSyncEstimator`, `ByteArrayPool`, `Fingerprint` and `PairingCode` (§6). No Android dependency. |
| `:transport` | Android lib | `Transport` interface; `LinkTransport`, the engine shared by every byte-stream link (blocking reader thread, writer thread with a §4 `SendQueue`, pooled video payloads, backoff); `TcpTransport` (127.0.0.1:47800, `TCP_NODELAY`); `AccessoryTransport` (AOA, one link per transport); `UsbAccessories` (UsbManager glue: find, permission, open, detach); `WifiTransport` (TLS 1.3, client certificate, pinning via `MacVerifier`); `PinStore`/`PinCodec`/`PinnedMacVerifier`; pure `TransportSelector`/`AccessoryIdentity`; `ReconnectPolicy`/`Backoff` (0.25 → 5 s). |
| `:decoder` | Android lib | `DecoderConfigPlanner` (pure: codec choice + `MediaFormat` keys), `CodecCatalog` (MediaCodecList → candidates, HELLO capabilities), `VideoDecoder` (async MediaCodec into a Surface, decode latency, error recovery). |
| `:renderer` | Android lib | `VideoSurfaceLayout` (SurfaceView, aspect fit), `LatestFramePresenter` (latest frame wins, `releaseOutputBuffer(i, System.nanoTime())`, end-to-end latency), `SurfaceFrameRate`. |
| `:input` | Android lib | `InputMapper` (pure: MotionEvent samples → INPUT, normalised to the video rect), `Tilt`, `InputCapture` (Android glue). |
| `:discovery` | Android lib | `MacDiscovery` + `NsdMacDiscovery` (`_tab2mac._tcp`, `registerServiceInfoCallback` on API 34+, serialized `resolveService` before), `TxtRecord`/`DiscoveredMac`. |
| `:app` | Application | `Session` (pure state machine, pairing included), `ReceiverController` (transports, discovery, WifiLock), `TabletIdentity` (AndroidKeyStore P-256 key and certificate), `KeystorePinStore` (AES-GCM sealed pins), `VideoPipeline`, `StreamStats`, `DeviceCapabilities` (HELLO from the real device), `AccessoryActivity` (invisible target of the accessory intent), `MainActivity` (home by states: `HomeModel`), `SettingsActivity`, `StreamActivity` (fullscreen stream, waiting sky, first-frame toast, diagnostics overlay), `ui/widget` (Ginga components). |

```text
:app ──► :transport ──► :protocol
  ├────► :renderer ──► :decoder
  ├────► :input ─────► :protocol
  └────► :discovery
```

Logging: `android.util.Log`, tags `T2M/<module>` (`T2M/app`, `T2M/session`, `T2M/transport`,
`T2M/decoder`, `T2M/renderer`, `T2M/input`, `T2M/discovery`), messages `event key=value …`:

```sh
adb logcat -s 'T2M/app:*' 'T2M/session:*' 'T2M/transport:*' 'T2M/decoder:*' 'T2M/renderer:*' 'T2M/input:*'
```

## Build and test

Requirements: JDK 17 and the Android SDK (platform 36, build-tools 36.0.0). Toolchain: Gradle 9.7.1
(wrapper), AGP 9.3.3 with built-in Kotlin, Kotlin 2.4.20, kotlinx-coroutines 1.11.0,
kotlinx-serialization 1.11.0, JUnit 4.13.2 — see `gradle/libs.versions.toml` for the
compatibility sources.

```sh
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
echo "sdk.dir=/opt/homebrew/share/android-commandlinetools" > local.properties   # once; gitignored
./gradlew test                 # every JVM unit test, including the golden vectors
./gradlew :app:assembleDebug   # → app/build/outputs/apk/debug/app-debug.apk
```

The wrapper (`gradlew`, `gradle/wrapper/gradle-wrapper.jar`) is committed. To regenerate it:
`gradle wrapper --gradle-version 9.7.1 --distribution-type bin`.

**Golden vectors.** `:protocol`'s `GoldenVectorTest` loads every `../protocol/test-vectors/*.json`
(written by the Swift implementation), decodes `hex` to exactly `decoded`, and re-encodes
`decoded` byte-exactly (JSON messages: same header and an equal JSON value). It is skipped, not
failed, when the directory is missing.

## Install and run (USB, `adb reverse`)

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb reverse tcp:47800 tcp:47800            # the Mac app / t2m does this for you
mac/.build/debug/t2m serve --synthetic     # or the Mac app; a test pattern without Screen Recording
```

Open Ginga on the tablet, choose **Cabo USB** and tap **Conectar pelo cabo**; the display opens
full screen once the Mac answers. Debug builds also take scripted commands:

```sh
adb shell am start -n dev.tab2mac.receiver/.ui.MainActivity --ez connect true
adb shell am start --activity-clear-top -n dev.tab2mac.receiver/.ui.MainActivity --ez disconnect true
adb shell am start -n dev.tab2mac.receiver/.ui.MainActivity --es appearance space   # system|light|dark|space
```

## UI (Ginga design system)

The UI follows `design/ginga-design/` (flows.md, "Tablet (Android)"): Views XML, no AndroidX.

- **Home** (`MainActivity`): one StatusOrbit pill at the top and one panel for where the
  connection is, computed by the pure `HomeModel.of(state, macs, chosenMethod)`: Procurando (radar),
  Mac encontrado (DeviceRows: Conectar / Reconectar / Parear de novo; touch and hold to forget),
  Cabo USB, Sem roteador (the §6b direct link), Pareando (the six digits in two groups;
  Parear / Não parear, then "Confirme no Mac"), Conectando, Conectado/Pausado (Mostrar tela,
  Desconectar). Chips pick Wi‑Fi · Cabo USB · Sem roteador while nothing is connected (USB is
  preselected when the Mac's accessory is attached). The technical line (`StatusText`: codec,
  ports, adb, the last session) is collapsed in **Diagnóstico**. The display opens by itself only
  when a stream *starts* while home is shown; Back from the display never reopens it.
- **Ajustes** (`SettingsActivity`): Reconectar automaticamente, Taxa preferida (Segmented: Mac
  decide / 60 Hz / 120 Hz, sent as a preference the Mac may ignore), Decodificação rápida,
  Aparência (Sistema / Claro / Escuro / Black espacial), Mostrar diagnóstico na tela (the overlay:
  fps, bitrate, decode and end-to-end p50/p95, drops, input count, panel refresh rate and
  frame-rate vote, battery current, RTT, clock offset), Avançado (adb instructions).
- **Stream** (`StreamActivity`): before the first frame, the sky (`cosmos`, `#000` in Black
  espacial) with `StarfieldView` (warp for 1.4 s, then twinkle at ~30 fps) and "Transmitindo de
  <Mac>"; the sky is GONE as soon as video shows, then a StatusOrbit toast "Conectado · 60 Hz ·
  Wi‑Fi" for 3 s. The video SurfaceView, the cursor view and input capture are unchanged.
- **Themes**: `Theme.Ginga.Light|Dark|Space` (framework Material parents) and
  `Theme.Ginga.System` (Light, Dark in `values-night`), colour attributes `?attr/ginga*` pointing
  at `values/ginga_colors.xml` (copied from the design). Stored as `ReceiverSettings.appearance`;
  changing it recreates the screen. Black espacial: every area `#000000`, cards only by a 1px
  `line` outline, a static star dust in each group's corner, a dithered pixel galaxy behind the
  home header and a black hole on the stream's waiting sky (`DitherField`, pure; `DitherView`,
  ~10 fps, only while shown).
- **Motion** (`Motion`): press 0.97 in 120 ms (`res/animator/g_press.xml`), `ease-ginga`
  (`res/interpolator/ease_ginga.xml`), orbit/pulse only while visible, rows rising 120 ms apart,
  pairing digits 60 ms apart, a 7-star spark when a switch turns on or a primary action is
  confirmed. Only transform and opacity, plus the two Canvas views. With the system's animations
  off (animator duration scale 0) nothing moves: static equivalents with the same text.
- **Type**: `TextAppearance.Ginga.*` in `values/styles.xml`. The three families are set in
  `TextAppearance.Ginga.FontDisplay|FontSans|FontSansMedium|FontMono` (platform sans-serif,
  sans-serif-medium, monospace today); drop Unbounded, Figtree and IBM Plex Mono into `res/font/`
  and change only those.
- **Languages**: `values-pt-rBR` (Portuguese, first) and `values` (English); `StringsTest` keeps
  them in step. `res/xml/locales_config.xml` enables Android's per-app language setting.

### adb loopback token

Any local process can reach 127.0.0.1:47800 — on the Mac, and on the tablet, where another app
would reach the Mac through `adb reverse`. So the Mac authorizes adb connections with a token
(32 random bytes, new on every Mac app start), delivered over adb right after `adb reverse`:

```sh
adb -s SERIAL shell 'read t; am broadcast -f 32 -a dev.tab2mac.action.LOOPBACK_TOKEN \
  -n dev.tab2mac.receiver/dev.tab2mac.receiver.adb.LoopbackTokenReceiver --es token "$t"'   # token on stdin
```

- `LoopbackTokenReceiver` is exported but guarded by `android.permission.DUMP`, which only the adb
  shell holds, so no other app can plant a token. It accepts exactly 64 lowercase hex digits and
  ignores anything else; the token is kept in memory and in app-private SharedPreferences
  (surviving an app restart) and never logged.
- HELLO carries `"loopbackToken"` over adb-tcp only — never over direct USB or Wi‑Fi. Without a
  token the tablet connects anyway, and the Mac refuses.
- The Mac answers a missing or wrong token with ERROR `unauthorized` and GOODBYE `error`. That is
  retryable: the usual backoff continues, and a token arriving meanwhile retries at once
  (`Transport.retryNow`). Home reads *"Aguardando o Mac autorizar · O Ginga está aberto no
  Mac?"* (Diagnóstico: *"Waiting for the Mac to authorize this USB connection. Is Ginga running
  on the Mac?"*).

## Direct USB (Android Open Accessory, M6)

No developer options, adb or network: Tab2Mac on the Mac switches the tablet into accessory mode,
and the protocol runs over the accessory's two bulk endpoints, framed exactly as over TCP.

1. **Plug in.** The Mac (direct USB enabled, this tablet approved) sends the AOA strings —
   manufacturer `Tab2Mac`, model `Tab2Mac Receiver`, description `Second display for your Mac`,
   version `1`, empty URI, serial `1` — then START. The tablet comes back as `18D1:2D00`
   (`2D01` when USB debugging is on, and adb keeps working next to the accessory).
2. **Prompt.** Android matches `res/xml/accessory_filter.xml` (manufacturer and model, exactly)
   and asks *"Open Ginga to handle Second display for your Mac?"* (the app label), with a
   checkbox *"Always open Ginga when Second display for your Mac is connected"* (AOSP wording; One UI may phrase it a
   little differently). OK grants access to the accessory. With **Always** ticked, later
   plug-ins open the app straight away, with no prompt.
3. **Connect.** `AccessoryActivity` (shows nothing) receives `USB_ACCESSORY_ATTACHED` and brings
   `MainActivity` to the front, closing a stream screen above it. `MainActivity` connects over the
   accessory and opens the display at once; the picture appears with the Mac's WELCOME and
   keyframe. HELLO says `"transport": "aoa"`. RECEIVER_REPORT and PING go out once a second.
4. **Disconnect and Connect.** Disconnect sends GOODBYE `user` and closes the descriptor; the
   accessory stays watched, and the status says *"Your Mac is connected by USB. Tap Connect…"*.
   While the cable stays in, the Mac offers a fresh link about a second after each session
   (PROTOCOL.md §5), so **Connect** opens the accessory again and says HELLO again — no replug.
5. **Unplug.** The session ends at once, through `ACTION_USB_ACCESSORY_DETACHED` or the pending
   read failing, whichever comes first. The app returns to *Not connected*: no retries, and no
   fallback to ADB. Plugging in again repeats 1–3.

If the prompt was dismissed, opening Ginga while the Mac's accessory is attached (or tapping
**Conectar pelo cabo**) shows *"Allow Ginga to access Second display for your Mac?"* and connects once
allowed. **Connect** always prefers the accessory when it is attached, and uses ADB otherwise.

- **Reconnecting by itself.** Android sends `USB_ACCESSORY_ATTACHED` only on a real attach, so a
  tablet that stays in accessory mode while the Mac app restarts (or this app is reinstalled)
  would never open the fresh link the Mac offers. With **Reconnect automatically** on:
  - the accessory transport reopens the accessory with the usual backoff after every link — the
    Mac restarted, GOODBYE `shutdown`, a silent Mac — for as long as it is attached and access is
    granted (`AccessoryTransport.RECONNECTING_OPTIONS`); each new link starts with a new HELLO;
  - when the app starts or comes to the foreground, an attached, permitted accessory is opened if
    no session runs, and replaces an ADB session that isn't streaming (`AccessoryAutoConnect`);
  - it stops on detach, on Disconnect, and after GOODBYE `user`/`replaced` from the Mac, until
    the next Connect or attach.
  With it off, a transport serves one link (`SINGLE_LINK_OPTIONS`) and **Connect** starts a new
  one. A busy device node (the previous descriptor still being released) is retried.
- **No handshake timeout.** Like the Mac on this link, the tablet waits for WELCOME as long as
  the link lasts: the Mac reads HELLO whenever Tab2Mac opens its side, even if it starts later.
- **Liveness.** Nothing signals a Mac that went away over USB: no FIN or RST, the pending read
  never returns and writes stop completing. Each link has a watchdog thread that never does I/O
  (`LinkOptions.silenceTimeoutMs`, 4 s here): on a streaming link (PING at 1 Hz, the Mac answers
  at once) a read that waited that long, or any write blocked that long, tears the link down —
  closing the descriptor unblocks the reader and writer — and the accessory is reopened. Time
  the reader spends held up by the session doesn't count, and a watchdog wake-up far later than
  planned (the app was frozen in the background) restarts the wait. GOODBYE `shutdown` (the Mac
  app quitting) also reopens; `user` doesn't.
- **Resynchronising.** A fresh link can begin with the tail of the previous link's last partial
  write. Until the first frame is parsed, the reader skips bytes up to the first plausible header
  (magic, framing version 1, a known or IGNORABLE type, length ≤ 16 MiB) and logs how many
  (`link.resynced`); after that, any bad header is a framing error as usual.
- **Reads.** `f_accessory` completes at most 16 KiB per read and has a single OUT request, so
  the Mac's writes wait whenever no read is queued. The reader thread issues blocking 64 KiB
  reads back to back (the kernel caps them at 16 KiB) and only parses between them. Closing the
  descriptor wakes a blocked read on Android; the transport doesn't depend on it.
- **Events, not polling.** Attach arrives as an activity intent; detach and the permission
  answer are broadcasts to receivers that only the system and this app can reach.

Tests (JVM): `AccessoryTransportTest` runs the transport over a fake `f_accessory` link — reads
of at most 16 KiB that never span two Mac transfers, and a pending read that local close
doesn't wake — covering frames split across reads, HELLO first, detach during a blocked read,
a failing link (no reopen), a gone or busy accessory, a local drop, suspend, and a new transport
reopening the accessory after a disconnect.
`TransportSelectorTest` and `AccessoryFilterTest` keep the selection, the filter XML, the
manifest and the Mac's strings in step.

## Pointer (CURSOR / CURSOR_SHAPE, §3.3b)

HELLO lists `cursor`. When WELCOME lists it too, the Mac leaves the pointer out of the video and
sends CURSOR (position, visibility, shape id) at up to the display rate, and CURSOR_SHAPE (a PNG
in stream pixels with its hotspot) once per shape per session; both are IGNORABLE binary
messages on stream 3.

- `CursorLayer` decodes each shape once, on the session thread, and caches it by id for the
  session (a `LongSparseArray`: no boxing); the cache is dropped when the stream stops.
- Positions only overwrite the latest one; the main thread applies it at most once per vsync
  (Choreographer): an `ImageView` above the video, moved with `translationX/Y` and scaled with
  `scaleX/Y` (view pixels per stream pixel) — no relayout, no GL, no allocation per message.
  `visible = 0` hides it. It takes no input: touches and the S Pen still reach the video.
- Placement (`CursorGeometry`, unit-tested): `x·videoWidth/65535 − hotspotX·s` inside the
  letterboxed video rect, `s` = video view width / stream width.

## Keyboard (KEY, §3.3c)

HELLO lists `keyboard`. While streaming to a Mac whose WELCOME lists it too, `StreamActivity`
forwards a hardware keyboard (the Book Cover, Bluetooth, USB) as physical keys: `KeyboardCapture`
takes only non-virtual, alphabetic keyboards (Back, volume and the tablet's navigation stay with
Android) and `HidKeyboard` maps each key to its USB HID usage on page 0x07 — by Linux scan code
first (the physical position; the Mac applies its own layout), by Android key code otherwise.
Covered: letters, digits, punctuation including ABNT2 (scan 89 → 0x87 International1, 86 → 0x64
Non-US \, keypad comma 0x85), F1–F24, navigation and editing keys, the keypad, Menu, and the
modifiers 0xE0–0xE7 (⊞/Samsung = left meta 0xE3). Modifiers are keys too; `modifiers` is the state
after the event. Repeats are more downs; keys still held when the window loses focus are
released. Keys without a usage (the DeX key) are not sent and stay with Android.

## Direct link, no router (§6b)

**Direct connection (no router)** on the connection screen, for places without a usable network:
the tablet hosts its own Wi‑Fi network, the Mac joins it, and the usual Wi‑Fi session (TLS 1.3,
pinning, pairing) runs on it. It needs the key a Mac hands over in DIRECT_LINK during an earlier
USB or Wi‑Fi session (kept per Mac in a Keystore-sealed file, never logged); the runtime
permissions (Bluetooth advertise/connect, nearby Wi‑Fi devices) are asked through the system
dialog.

1. **Network.** A Wi‑Fi Direct autonomous group (`DIRECT-T2-<first 4 hex of keyId>`, a random
   24-character passphrase per link, not persistent), on the channel of the tablet's own 5 GHz
   Wi‑Fi when it has one, else any 5 GHz channel; a local-only hotspot if that fails.
2. **Bluetooth LE.** A GATT service (`5432D1EC-…0001`, advertised, balanced mode): the
   credentials characteristic serves `{ssid, psk, session, expires}` sealed with AES-256-GCM (HKDF
   subkey, AAD = keyId), with a fresh nonce and a 5-minute expiry on every read; the address
   characteristic takes the Mac's sealed `{host, port, session}`. Refused: another key or
   tampering, another session's address (a replay), an address after the credentials expired,
   a second address.
3. **Session.** The tablet connects to that host and port like any Wi‑Fi Mac (TLS, pinning by the
   Mac's certificate, pairing if it isn't pinned). Bluetooth LE stops once connected.
4. **End.** The network and Bluetooth LE go when the session ends, on Cancel, or on any failure
   (`DirectLinkFlow`, unit-tested with the §6b vectors both ways, refusals and teardown).

Measured on the Tab S11 (tablet side only, no Mac yet):

| | Wi‑Fi Direct group | Local-only hotspot |
|---|---|---|
| Up in | ≈ 0.1 s | ≈ 0.2 s |
| Band / channel | 5 GHz, on the tablet's own Wi‑Fi channel (5805 MHz here) | 2.4 GHz, 20 MHz (2412 MHz): this region allows 5 GHz SoftAP only on channel 149 |
| Name, passphrase | ours (`DIRECT-T2-0102`, per link) | the system's (`AndroidShare_…`) |
| Normal Wi‑Fi | stays connected | stays connected |
| Idle limit | none | the system stops it after 10 min without clients |

Wi‑Fi Direct is the better choice: 5 GHz and a single channel shared with the tablet's own Wi‑Fi
(no radio hopping between channels), our credentials, and no idle shutdown. Without the
same-channel request the group landed on another 5 GHz channel (5200/5785 MHz) than the
tablet's Wi‑Fi (5805 MHz), i.e. multi-channel concurrency. The hotspot is only a fallback.
The battery drain couldn't be measured alone: the tablet sat on its charger at its charge limit
(AC powered, not charging), where the battery current says nothing; this needs the joint test
off the charger.

## Wi‑Fi (M7)

Chosen explicitly: the connection screen lists the Macs advertising `_tab2mac._tcp` on the
network (TXT `pv`, `id`, `name`), and **Connect** on a row starts a Wi‑Fi session. USB keeps
priority: attaching the Mac's accessory replaces a Wi‑Fi session. Discovery (`NsdManager`) runs
only while the connection screen is visible. The Mac's port is chosen by the system each time
Tab2Mac starts, so its service is resolved again (`NsdMacResolver`, one mDNS query) before every
connection attempt, reconnections included.

- **Tablet identity.** A P-256 key generated in the AndroidKeyStore (it never leaves the secure
  hardware) with the self-signed certificate the KeyStore issues for it (`CN=Tab2Mac tablet`,
  ECDSA-SHA256, 20 years). Its fingerprint — SHA-256 of the certificate's DER — is what the Mac
  pins. The key allows digest `NONE` besides SHA-256, because TLS signs the handshake digest it
  computed itself. Clearing the app's data deletes the identity: the tablet then pairs again.
- **TLS.** TLS 1.3 only, over a TCP socket with `TCP_NODELAY`; the tablet presents its
  certificate (the Mac requires one). The handshake accepts any server certificate; right after
  it, before a single byte of the protocol, the Mac's certificate fingerprint is checked
  (`MacVerifier`). Then the same framing, blocking reader and `SendQueue` writer as every other
  link. Drops reconnect with the usual backoff; each new link is checked again, and HELLO carries
  the session token (`resume`). GOODBYE `user` (the Mac forgot the tablet, or turned Wi‑Fi off)
  ends the session without reconnecting.
- **Pinned Mac.** Pins are kept by the Mac's TXT `id`. A pinned Mac presenting another certificate
  is refused before HELLO: the row says *"Its identity changed"* and offers **Pair again**, which
  forgets the old pin first. Touch and hold a paired Mac to forget it.
- **Asking to pair.** Whenever the tablet has no pin matching the certificate the Mac just
  presented (never paired, forgotten, or **Pair again** after an identity change, which forgets
  the old pin first), its HELLO carries `"pairingRequested": true`, so the Mac pairs even if it
  still pins the tablet, and replaces its pin on success. Never sent over adb or direct USB.
- **Pairing** (a Mac that isn't pinned; HELLO lists `pairing` over Wi‑Fi): numeric comparison
  with a commitment, so a man in the middle gets one guess at the code per attempt instead of
  grinding certificates offline (`PairingCode`, `Session.onPairing`):
  1. The Mac sends PAIRING `required` with its name.
  2. The tablet draws a fresh 32-byte nonce and sends `commit` with
     `SHA-256(tabletFP ‖ macFP ‖ tabletNonce)`. No code yet.
  3. The Mac sends its `nonce`.
  4. The tablet sends `reveal` with its nonce, then shows the code `053 656`: the first 4 bytes of
     `SHA-256(macFP ‖ tabletFP ‖ macNonce ‖ tabletNonce)`, big-endian, mod 1 000 000
     (vector: 0x11 / 0x22 fingerprints, 0x33 / 0x44 nonces → commitment `052c9571…`, code `053656`).
  5. **Codes match** sends `confirmed` (only possible once the code is shown). **Cancel** — or
     Disconnect — sends `rejected`, GOODBYE `user`, and closes.
  6. On `paired` the tablet pins {id, name, fingerprint}; WELCOME follows.
  Anything missing, repeated, out of order or malformed from the Mac, and the 2-minute timeout,
  end the attempt with `rejected` and GOODBYE `error`; a `rejected` from the Mac ends the session;
  unknown states are ignored. No trust on first use, as a safety net for a Mac too old to honour
  `pairingRequested`: a Mac that answers HELLO with WELCOME without a pin on the tablet gets
  GOODBYE `error`, and the status says *"Forget this tablet on the Mac, then connect again"*.
- **Where pins live.** `noBackupFilesDir/wifi-pins`: JSON sealed with AES-256-GCM under a key in
  the AndroidKeyStore. A missing or tampered file reads as "no pins", so Macs ask to pair again.
- **Power.** `WIFI_MODE_FULL_LOW_LATENCY` is held only while a Wi‑Fi stream is live and on screen;
  it is released on pause, when the display is hidden, and on disconnect. RECEIVER_REPORT goes out
  every 250 ms (the Mac's bitrate controller adapts to it); PING stays at 1 Hz.

Tests (JVM): `WifiTransportTest` runs the transport against a real TLS 1.3 server on loopback
with self-signed P-256 certificates on both sides (mutual authentication, the Mac's fingerprint
in `Connected`, a pinned Mac accepted, an impostor refused before any byte, reconnection, the
Mac looked up again before each attempt — including after it moved to another port);
`PinsTest`, `PairingCodeTest` (the §6 vector), the pairing cases in `SessionTest` (the whole
exchange, decline, out-of-order/repeated/malformed steps, timeout, fresh nonces, no trust on
first use), and the TXT cases in `TxtRecordTest`.

## Power

Minimum battery use at the best latency the tablet allows. Each rule, and where it lives:

1. **Zero-copy render** — MediaCodec renders straight into the SurfaceView's Surface; no GL,
   TextureView, ImageReader or CPU access to decoded frames (`VideoDecoder`, `LatestFramePresenter`).
   Frames are released with `releaseOutputBuffer(index, System.nanoTime())` rather than
   `releaseOutputBuffer(index, true)`: both are the same zero-copy path, but `true` would hand
   SurfaceFlinger our presentation timestamp, which is the *Mac* capture clock.
2. **Decoder** — async callbacks; hardware-accelerated decoders only, never a software fallback;
   `low-latency=1`, `priority=0`, `operating-rate` = stream fps (never `Short.MAX_VALUE`); MediaTek
   `vdec-lowlatency=1` and post-processing (`vendor.mtk.ext.vdec.vpp.disabled.value=1`) off
   (`DecoderConfigPlanner`). The **Faster decoding** setting sets `operating-rate` = 2 × fps.
3. **Panel refresh** — `Surface.setFrameRate(streamFps, FIXED_SOURCE, CHANGE_FRAME_RATE_ALWAYS)`,
   updated when WELCOME/CONFIGURE change the rate (`StreamActivity.voteFrameRate`). Verified: a
   60 fps stream switches the Tab S11 panel from 120 Hz to 60 Hz (`dumpsys SurfaceFlinger`:
   `activeMode … vsyncRate=60.00 Hz`); touches boost it back to 120 Hz for a few seconds, as usual.
4. **Nothing runs when nothing changes** — the socket or accessory reader blocks on its own
   thread; there is no polling: the session's timer sleeps until its next deadline (`Session.nanosUntilNextTick`),
   which is PING + RECEIVER_REPORT once a second while streaming and nothing while idle. The
   overlay is off by default and refreshes at 1 Hz only while shown; while it is hidden, frame
   latencies are sampled 1 in 4. Reports are 1 Hz because USB has no bitrate adaptation
   (architecture §2.5); Wi‑Fi sends them every 250 ms for the Mac's bitrate controller. Network
   discovery runs only while the connection screen is visible.
5. **No video without a screen** — when the stream's Surface goes away (Home, Back, screen off)
   for 1 s, the session sends CONFIGURE `{"request":{"paused":true}}` (WELCOME feature `pause`):
   the Mac stops capturing and encoding; PING stays at 1 Hz and reports drop to one per 5 s.
   `paused:false` follows as soon as the Surface is back, and the Mac answers with a keyframe.
   A Mac without `pause` gets GOODBYE `user` after 10 s; the transport is suspended (no
   reconnection attempts) until the display is shown again.
6. **No per-frame garbage** — received VIDEO_FRAME payloads come from a `ByteArrayPool` (fixed
   slots, no boxing) and are decoded as zero-copy views; the decoder hands each buffer back as
   soon as it's copied into a codec buffer (`Incoming` is the `AutoCloseable` owner, so no
   callback is allocated); decode timing uses a fixed ring and primitive fields; frame headers
   are parsed and written in place; input samples reuse the same objects. A few small message
   objects per frame/event remain.
7. **No hidden queues** — 8 received messages at most between socket and session, the system's
   default socket buffer, and a decoder backlog limited by age: when the oldest delta frame
   waiting for the codec is older than two frame intervals, the backlog is dropped and a keyframe
   requested, so latency can't pile up.
8. **Screen and locks** — `FLAG_KEEP_SCREEN_ON` only while a stream is live and decoding (cleared
   on pause, disconnect and decoder failure); no WakeLock. The Wi‑Fi low-latency lock only while
   a Wi‑Fi stream is live on screen.
9. **Input** — default vsync-batched delivery; each `MotionEvent`'s historical samples go out as
   one batch (one socket write). `requestUnbufferedDispatch` only while the S Pen touches.
10. **Reporting** — decode latency, fps, end-to-end latency, panel refresh and
    `BATTERY_PROPERTY_CURRENT_NOW` (mA, and W with the battery voltage) in the overlay. While the
    tablet is plugged into the Mac the current is the net charge current.

## Measured on the Tab S11 (SM‑X730, Dimensity 9400+, Android 16)

Measured before the review fixes (pause, smaller buffers, age-limited backlog, sampling); those
still need a run on the tablet.

`t2m serve --synthetic` (2560×1600 HEVC test pattern, very low bitrate) over USB/`adb reverse`,
decoder `c2.mtk.hevc.decoder.lowlatency`; RECEIVER_REPORT figures as printed by the Mac:

| Configuration | fps | decode p50 | end-to-end p50 / p95 |
|---|---|---|---|
| 60 fps, `operating-rate` 60 (default), panel 60 Hz | 60 | 14–15 ms | 23–26 / 28–35 ms |
| 60 fps, `operating-rate` 120 (Faster decoding) | 60 | ≈ 11.2 ms | ≈ 20.3 / 23–25 ms |
| 120 fps stream, panel 120 Hz | 120 | ≈ 9.2 ms | ≈ 18.8 / 25–34 ms |
| First build: 60 fps, panel voted 120 Hz, no `operating-rate` | 60 | ≈ 14.4 ms | ≈ 24 / 47–59 ms |

The M4 gate (end-to-end p50 ≤ 40 ms at 60 Hz) passes. The MediaTek decode latency is above the
10 ms budget unless the decoder gets clock headroom: that is the latency/power trade-off to
settle with real desktop content and a battery measurement off USB.

CPU at 60 fps: the app process uses about half of one core, mostly the framework's own
`MediaCodec_loop` thread (≈ 18 %); wake-ups are per frame (reader ≈ 61/s, session ≈ 147/s,
decoder callbacks ≈ 195/s), no timers.

## Connection behaviour

- **Backoff** (0.25 → 5 s) is reset only after WELCOME (`Transport.markHealthy`): a Mac that
  accepts and then refuses the tablet is retried with growing delays, never in a loop.
- **ERROR `unauthorized`** (adb loopback token missing or stale) is retried, see above.
- **ERROR before WELCOME** with `unsupported`, `internal` or `incompatible-version` is final: the
  session ends and shows the Mac's message. After WELCOME, ERRORs are only reported.
- **GOODBYE** `user`/`replaced` ends the session. Any other GOODBYE closes the connection from
  the tablet side too, and the transport reconnects with backoff.
- **Loss**: the Mac never drops encoded frames, so a gap in `frameId` (for example a VIDEO_FRAME
  the transport couldn't decode) triggers KEYFRAME_REQUEST `loss`. A frame larger than the
  codec's input buffers restarts the codec with twice that size (a keyframe is then decoded; a
  delta frame waits for a keyframe).
- **Rotation**: CONFIGURE `request.orientation` is compared with the last orientation requested
  on the connection (not with the display announced in WELCOME), so rotating back is sent.
- **Clock sync**: the transport stamps PING `t1` and PONG `t3` as the frame is written.
- **Liveness**: the transport's watchdog thread (no I/O) drops a streaming link that received
  nothing for 5 s (4 s over direct USB), or whose write stayed blocked that long; every transport
  then reconnects with backoff ("Reconnect automatically").
- **Failures** in the session's coroutines end the session (GOODBYE `error`), never the app.
  STREAM_FORMAT with impossible dimensions is answered with ERROR `bad-frame` and ignored.

## Protocol decisions

- **Unknown message types** decode as `UnknownMessage`: the session skips IGNORABLE ones and
  answers the others with `ERROR unsupported` naming the type, keeping the connection (a framing
  error — bad magic/fver/length — sends `ERROR bad-frame` and closes, per §2). PAIRING (0x07) is
  sent with IGNORABLE; over USB it is ignored.
- **POINTER_DOWN / POINTER_UP**: v1 has no field for the pointer that changed, so it is the
  **first** pointer record, followed by the others.
- **Tilt**: `AXIS_TILT` + `AXIS_ORIENTATION` → tiltX/tiltY with the W3C Pointer Events convention
  (positive X leans the pen's top end to the right, positive Y towards the user), as Chromium does.
- **HELLO `display`**: current-orientation pixels, `densityDpi` = physical DPI (xdpi/ydpi, as in
  the spec's 274 example), `rotation` in degrees.
- **Preferred refresh rate**: only when the user picks 60 or 120 Hz, sent after WELCOME as
  `CONFIGURE {request: {refreshRate}}`, a preference the Mac may ignore. The default sends nothing.
- **Features**: HELLO lists `clock-sync`, `receiver-report`, `pause` and `cursor`, plus `pairing`
  over Wi‑Fi.
- **HELLO `transport`**: `adb-tcp`, `aoa`, or `wifi-tls` (informational; the Mac never derives
  trust from it). `loopbackToken` only with `adb-tcp`.
- **PING/PONG** have no header length; extra trailing bytes are ignored.
- **Codec names**: `hevc`/`h265` → `video/hevc`, `h264`/`avc` → `video/avc`.
- **RECEIVER_REPORT** `rttUs` is the latest round trip, `clockOffsetUs` the θ of the minimum-RTT
  sample of the last 16.

## Not done yet

- **On-device check of the review fixes**: pause/resume and the no-`pause` suspend path, the
  age-limited backlog, sampling and the new measurements need the tablet unlocked.

- **M5 polish**: gestures are left to the Mac; palm rejection only via `FLAG_CANCELED`; no pen
  hover preview on the tablet; rotation was not exercised on the device (it needs the user).
- **M6 on the tablet**: the accessory flow (prompt, auto-connect, Disconnect/Connect, unplug,
  throughput with 16 KiB reads) has only run in JVM tests; it needs the user at the tablet.
- **M7 on the tablet**: discovery, the KeyStore identity through Conscrypt, pairing with the real
  Mac and the WifiLock have only run in JVM tests (the TLS part against JSSE, not Conscrypt).
  Not handled: `ACCESS_LOCAL_NETWORK` before targetSdk 37, and the UDP video profile (M8).
- An instrumented decode test with a recorded HEVC fixture (milestones M4), ADPF hint sessions,
  and a reader-thread fast path for video (it would save one thread hop per frame, but STREAM_FORMAT
  and keyframes must then take the same path to stay ordered).
