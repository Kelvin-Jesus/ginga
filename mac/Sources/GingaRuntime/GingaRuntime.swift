import CGVirtualDisplayBackend
import DirectLink
import DisplayCapture
import Foundation
import GingaCore
import GingaSecurity
import GingaSession
import GingaStreaming
import Transport
import USBAccessory
import VirtualDisplay

/// Everything Ginga runs, wired once for both front ends: the app (menu bar, control panel)
/// and `ginga run` (headless, for the smallest footprint). The composition root is here, the only
/// place that picks the virtual display backend.
@MainActor
public final class GingaRuntime {
    public let session: DisplaySession
    public let host: DisplayStreamHost
    public let server: StreamServer
    public let accessories: AccessoryCoordinator
    public let wifi: WiFiService
    public let directKeys: KeychainDirectKeyStore
    public let direct: DirectLinkSession
    public let inputRouter = InputRouter()
    public let macName: String
    private var powerMonitor: PowerSourceMonitor?

    /// - Parameters:
    ///   - loopbackToken: the token adb connections must present (generated per launch if nil).
    ///   - pairingPresenter: how the Mac's user confirms a Wi‑Fi pairing code.
    public init(configuration: GingaConfiguration, loopbackToken: String? = nil, pairingPresenter: (@MainActor (PairingRequest) -> Void)?) {
        macName = Host.current().localizedName ?? "Mac"
        let provider = VirtualDisplayProvider(backend: CGVirtualDisplayBackend())
        session = DisplaySession(provider: provider, capture: ScreenCaptureKitSource(), configuration: configuration, captureEnabled: false)
        host = DisplayStreamHost(session: session)
        let inputRouter = inputRouter
        inputRouter.settings = configuration.input
        host.inputHandler = { input, display in inputRouter.handle(input, display: display) }
        host.inputEndHandler = { inputRouter.reset() }
        host.keyHandler = { key in inputRouter.handleKey(key) }

        server = StreamServer(host: host, settings: configuration.streaming)
        server.requireLoopbackToken(loopbackToken ?? LoopbackToken.generate())
        server.pairingPresenter = pairingPresenter
        directKeys = KeychainDirectKeyStore()
        server.directKeys = directKeys

        // Direct USB (M6): approved tablets are switched to accessory mode when plugged in.
        accessories = AccessoryCoordinator(isEnabled: configuration.streaming.directUSB, approvedSerials: Set(configuration.streaming.approvedUSBDevices))
        let server = server
        // No HELLO timeout: the tablet app starts only after the user answers Android's prompt.
        accessories.onConnection = { [weak server] connection in server?.accept(connection, helloTimeout: .some(nil)) }

        wifi = WiFiService(server: server)
        let wifi = wifi
        let macName = macName
        direct = DirectLinkSession(
            keys: directKeys, channel: BluetoothCredentialChannel(), wifi: CoreWLANWiFi(),
            listenerPort: { await wifi.ensureRunning(macName: macName) },
            closeSessions: { [weak server] in await server?.closeWiFiSessions(reason: "direct link ended") }
        )
    }

    public var backendIdentifier: String { session.provider.backendIdentifier }

    /// Starts what the configuration asks for; nothing polls. `serveUSB` also opens the adb listener.
    public func start(serveUSB: Bool) throws {
        let session = session
        // 120 Hz on the power adapter, `power.batteryRefreshRate` (60 Hz) on battery.
        Task { await session.setOnBattery(PowerSource.isOnBattery) }
        powerMonitor = PowerSourceMonitor { onBattery in Task { await session.setOnBattery(onBattery) } }
        accessories.start()
        if session.configuration.streaming.wifi { wifi.start(macName: macName) }
        if serveUSB { try server.start() }
    }

    /// Quitting: tablets hear GOODBYE "shutdown", and a direct link returns the Mac to its network.
    public func shutdown() {
        server.shutdown()
        guard direct.isActive else { return }
        var done = false
        let direct = direct
        Task { @MainActor in
            await direct.end()
            done = true
        }
        let deadline = Date().addingTimeInterval(8)
        while !done, Date() < deadline { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }
}
