# Diagrams

Mermaid diagrams of the moving parts. The text of record is [architecture.md](architecture.md) and [PROTOCOL.md](../protocol/PROTOCOL.md); update both when a diagram changes.

## System

```mermaid
flowchart LR
  subgraph Mac
    VD[Virtual display<br/>CGVirtualDisplay shim] --> WS[[WindowServer]]
    WS --> CAP[ScreenCaptureKit<br/>420v, on demand]
    CAP --> ENC[VideoToolbox HEVC<br/>pacer · cadence]
    ENC --> SRV[StreamServer<br/>sessions · leases · liveness]
    CUR[CursorTracker] --> SRV
    SRV --> INJ[InputRouter<br/>touch · pen · keys]
  end
  subgraph Links
    AOA[Direct USB<br/>AOA bulk pipes]
    ADB[adb reverse<br/>+ loopback token]
    WIFI[Wi‑Fi TLS 1.3<br/>pinned]
    DIRECT[Tablet's own network<br/>no router]
  end
  subgraph Tablet
    RX[Session] --> DEC[MediaCodec<br/>low latency]
    DEC --> VIEW[SurfaceView + cursor overlay]
    IN[Touch · S Pen · keyboard] --> RX
  end
  SRV <--> AOA <--> RX
  SRV <--> ADB <--> RX
  SRV <--> WIFI <--> RX
  SRV <--> DIRECT <--> RX
```

## Module dependencies (Mac)

```mermaid
flowchart TD
  App[Tab2MacApp] --> Runtime[Tab2MacRuntime]
  CLI[t2m] --> Runtime
  Runtime --> Streaming[Tab2MacStreaming]
  Runtime --> USB[USBAccessory] --> Shim2[USBAccessoryShim · Obj‑C]
  Runtime --> Direct[DirectLink]
  Runtime --> Input[InputInjection]
  Runtime --> Backend[CGVirtualDisplayBackend] --> Shim[CGVirtualDisplayShim · Obj‑C · private API]
  Streaming --> Session[Tab2MacSession] --> VD[VirtualDisplay]
  Session --> Capture[DisplayCapture]
  Streaming --> Pipeline[VideoPipeline]
  Streaming --> Protocol[Tab2MacProtocol]
  Streaming --> Transport
  Streaming --> Security[Tab2MacSecurity]
  Direct --> Security
  CLI --> Energy[EnergyMeter · IOReport]
```

## Session setup (every link)

```mermaid
sequenceDiagram
  participant T as Tablet
  participant M as Mac
  T->>M: HELLO (versions, device, display, decoders, features[, loopbackToken][, pairingRequested])
  alt adb without the right token
    M->>T: ERROR unauthorized, GOODBYE error
  else Wi‑Fi, tablet not pinned (or pairingRequested)
    Note over T,M: pairing (below)
  end
  M->>M: lease: display (shaped for this device), capture demand
  M->>T: WELCOME (display, stream fps ≤ decoder, features)
  opt direct-link
    M->>T: DIRECT_LINK (key)
  end
  M->>T: STREAM_FORMAT, VIDEO_FRAME [keyframe]
  loop
    T->>M: PING (1 Hz) → PONG
    T->>M: RECEIVER_REPORT
    M->>T: VIDEO_FRAME (on change) · CURSOR (on move)
    T->>M: INPUT · KEY
  end
```

## Pairing with commitments (Wi‑Fi)

```mermaid
sequenceDiagram
  participant T as Tablet
  participant M as Mac
  M->>T: PAIRING required
  T->>M: PAIRING commit (SHA-256(tabletFP ‖ macFP ‖ nT))
  M->>T: PAIRING nonce (nM)
  T->>M: PAIRING reveal (nT)
  Note over M: checks the commitment
  Note over T,M: both show code(macFP, tabletFP, nM, nT)
  T->>M: PAIRING confirmed
  Note over M: the Mac's user confirms
  M->>T: PAIRING paired → WELCOME
```

## No router (direct link)

```mermaid
sequenceDiagram
  actor U as User
  participant T as Tablet
  participant M as Mac
  U->>T: Direct connection
  T->>T: Wi‑Fi Direct group (5 GHz, new passphrase) + BLE GATT service
  U->>M: Connect directly to the tablet
  M->>M: Location permission (to see networks)
  M->>T: BLE read: sealed {ssid, psk, session, expires}
  M->>M: remember current network, join the tablet's (CoreWLAN)
  M->>T: BLE write: sealed {host, port, session}
  T->>M: TLS connect → HELLO … (usual Wi‑Fi session)
  Note over M: session ends / user ends / tablet gone 10 s
  M->>T: GOODBYE (tablet takes its network down)
  M->>M: leave; wait ≤ 15 s for macOS auto-join
  opt still on no network
    M->>M: join the previous network from the last scan, else cycle Wi‑Fi
  end
```

## Direct USB (accessory) link lifecycle

```mermaid
stateDiagram-v2
  [*] --> Candidate: Android device attached
  Candidate --> Switching: approved (user)
  Switching --> Accessory: AOA 51/52/53, re-enumerates as 18D1:2D00/01
  Accessory --> Linked: approved serial → MessageConnection
  Linked --> Streaming: HELLO
  Streaming --> Linked: session ends (GOODBYE / silence 5 s) → fresh link after 1 s
  Streaming --> Streaming: HELLO again (app restarted)
  Linked --> [*]: detached / revoked / direct USB off
```

## Receivers on the Mac

```mermaid
stateDiagram-v2
  [*] --> pending: connection accepted
  pending --> pending: HELLO / pairing / preparing
  pending --> current: streaming (replaces the previous current)
  pending --> [*]: closed (HELLO timeout, refused, too many pending)
  current --> current: paused ↔ resumed (activity only while not paused)
  current --> [*]: closed / silent 5 s / replaced
```
