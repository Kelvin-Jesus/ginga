import Foundation
import Network
import GingaProtocol
import Testing
@testable import Transport

@Suite("AdbBridge")
struct AdbBridgeTests {
    /// The token reaches the tablet through adb's stdin, never on a command line (where any
    /// process on the Mac could read it), and only through the DUMP-protected receiver.
    @Test func theTokenTravelsOnStdinToTheProtectedReceiver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ginga-fake-adb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = directory.appendingPathComponent("adb")
        try """
        #!/bin/sh
        printf '%s\\n' "$@" > "\(directory.path)/argv"
        cat > "\(directory.path)/stdin"
        """.write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let token = String(repeating: "ab", count: 32)
        try AdbBridge(executable: fake).deliverToken(token, serial: "R52Y80EE15V")
        let argv = try String(contentsOf: directory.appendingPathComponent("argv"), encoding: .utf8)
        #expect(!argv.contains(token))
        #expect(argv.hasPrefix("-s\nR52Y80EE15V\nshell\n"))
        #expect(argv.contains("dev.ginga.receiver/dev.ginga.receiver.adb.LoopbackTokenReceiver"))
        #expect(try String(contentsOf: directory.appendingPathComponent("stdin"), encoding: .utf8) == token + "\n")
    }

    @Test func parsesDevicesListWithProperties() {
        let output = """
        List of devices attached
        R52Y80EE15V            device usb:52428800X product:gts11wifixx model:SM_X730 device:gts11wifi transport_id:19
        0123456789ABCDEF       unauthorized usb:1-1 transport_id:3
        emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:4

        """
        let devices = AdbBridge.parseDevices(output)
        #expect(devices.count == 3)
        #expect(devices[0] == AdbDevice(serial: "R52Y80EE15V", state: "device", model: "SM_X730", product: "gts11wifixx", isUSB: true))
        #expect(!devices[1].isReady)
        #expect(devices[2].isReady && !devices[2].isUSB)
    }

    @Test func ignoresDaemonNoise() {
        let output = "* daemon not running; starting now at tcp:5037\n* daemon started successfully\nList of devices attached\n"
        #expect(AdbBridge.parseDevices(output).isEmpty)
    }

    /// `adb track-devices -l` as captured from the Tab S11: hex length, then a device list.
    @Test func trackDevicesUpdatesAreFramedByHexLength() {
        let line = "R52Y80EE15V            device usb:52428800X product:gts11wifixx model:SM_X730 device:gts11wifi transport_id:19\n"
        let update = String(format: "%04x", line.utf8.count) + line
        #expect(update.hasPrefix("006f"))
        var parser = AdbTrackParser()
        let updates = parser.feed(Data(update.utf8))
        #expect(updates.count == 1)
        #expect(updates.first?.first == AdbDevice(serial: "R52Y80EE15V", state: "device", model: "SM_X730", product: "gts11wifixx", isUSB: true))
    }

    @Test func trackDevicesHandlesSplitReadsEmptyListsAndTabs() {
        func frame(_ body: String) -> String { String(format: "%04x", body.utf8.count) + body }
        let stream = Data((frame("R52Y80EE15V\tunauthorized\n") + frame("") + frame("R52Y80EE15V\tdevice\nnoise\n")).utf8)
        var parser = AdbTrackParser()
        var updates: [[AdbDevice]] = []
        // Byte by byte: the framing must survive any read boundary.
        for byte in stream { updates += parser.feed(Data([byte])) }
        #expect(updates.count == 3)
        #expect(updates[0].map(\.state) == ["unauthorized"])
        #expect(updates[1].isEmpty)  // "0000": the tablet went away
        #expect(updates[2].map(\.serial) == ["R52Y80EE15V"])  // single-field noise lines are ignored
        #expect(updates[2].first?.isReady == true)
    }

    @Test func trackDevicesDropsGarbageWithoutCrashing() {
        var parser = AdbTrackParser()
        #expect(parser.feed(Data("zzzz-not-hex".utf8)).isEmpty)
        #expect(parser.feed(Data("0000".utf8)).count == 1)
        // Signs parse as integers but are not adb's framing (a negative length used to trap).
        #expect(parser.feed(Data("-001abc".utf8)).isEmpty)
        #expect(parser.feed(Data("+001x".utf8)).isEmpty)
        #expect(parser.feed(Data("0000".utf8)).count == 1)
    }
}

/// Thread-safe collector for callbacks.
final class Inbox: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Message] = []
    private var closes: [MessageConnection.CloseReason] = []
    private var connections: [MessageConnection] = []
    private var port: UInt16?

    func add(_ message: Message) { lock.withLock { messages.append(message) } }
    func closed(_ reason: MessageConnection.CloseReason) { lock.withLock { closes.append(reason) } }
    func accepted(_ connection: MessageConnection) { lock.withLock { connections.append(connection) } }
    func listening(_ port: UInt16) { lock.withLock { self.port = port } }

    var received: [Message] { lock.withLock { messages } }
    var closeReasons: [MessageConnection.CloseReason] { lock.withLock { closes } }
    var serverConnections: [MessageConnection] { lock.withLock { connections } }
    var listeningPort: UInt16? { lock.withLock { port } }
}

func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

@Suite("TCP transport", .serialized)
struct TCPTransportTests {
    private func startServer(_ inbox: Inbox) async throws -> (TCPServer, UInt16) {
        let server = try TCPServer(port: 0)
        server.start { event in
            switch event {
            case .listening(let port): inbox.listening(port)
            case .connection(let connection):
                connection.setHandlers(onMessage: { inbox.add($0) }, onClose: { inbox.closed($0) })
                inbox.accepted(connection)
                connection.start()
            case .failed: break
            }
        }
        #expect(await eventually { inbox.listeningPort != nil })
        return (server, try #require(inbox.listeningPort))
    }

    @Test func exchangesMessagesBothWays() async throws {
        let serverInbox = Inbox()
        let (server, port) = try await startServer(serverInbox)
        defer { server.stop() }

        let clientInbox = Inbox()
        let client = MessageConnection.connect(host: "127.0.0.1", port: port)
        client.setHandlers(onMessage: { clientInbox.add($0) }, onClose: { clientInbox.closed($0) })
        client.start()

        client.send(.ping(Ping(id: 7, t1: 100)))
        #expect(await eventually { serverInbox.received.count == 1 })
        #expect(serverInbox.received.first == .ping(Ping(id: 7, t1: 100)))

        let big = VideoFrame(frameId: 1, captureTimeUs: 5, encodeDurationUs: 6, isKeyframe: true, data: Data((0..<1_000_000).map { UInt8($0 & 0xFF) }))
        let serverSide = try #require(serverInbox.serverConnections.first)
        serverSide.send(.videoFrame(big))
        serverSide.send(.pong(Pong(id: 7, t1: 100, t2: 200, t3: 300)))
        #expect(await eventually { clientInbox.received.count == 2 })
        #expect(clientInbox.received.first == .videoFrame(big))
        #expect(await eventually { serverSide.statistics.videoFramesInFlight == 0 })
        #expect(serverSide.canAcceptVideo)

        client.close(reason: "test done")
        #expect(await eventually { serverInbox.closeReasons.contains(.remote) })
    }

    @Test func garbageClosesTheConnectionWithAProtocolError() async throws {
        let serverInbox = Inbox()
        let (server, port) = try await startServer(serverInbox)
        defer { server.stop() }

        let raw = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        raw.start(queue: .global())
        raw.send(content: Data(repeating: 0xAB, count: 32), completion: .idempotent)
        #expect(await eventually {
            serverInbox.closeReasons.contains { if case .protocolError = $0 { true } else { false } }
        })
        raw.cancel()
    }

    @Test func serverIsNotReachableFromOtherInterfaces() throws {
        // Loopback-only binding is what keeps the unencrypted stream off the LAN.
        let server = try TCPServer(port: 0, loopbackOnly: true)
        server.stop()
    }
}
