import Foundation
import os
import Tab2MacCore

public struct AdbDevice: Hashable, Sendable {
    public var serial: String
    /// "device" when authorized; "unauthorized", "offline", … otherwise.
    public var state: String
    public var model: String?
    public var product: String?
    public var isUSB: Bool

    public var isReady: Bool { state == "device" }
}

/// USB transport via the user's `adb` (never bundled — see research §5.1): finds tablets and
/// keeps `adb reverse tcp:PORT tcp:PORT` in place so the tablet's 127.0.0.1:PORT reaches us.
///
/// Event-driven: one long-lived `adb track-devices` pushes device changes, so nothing polls and
/// no process is spawned while nothing changes.
public final class AdbBridge: @unchecked Sendable {  // mutable state is guarded by `lock`
    public let executable: URL
    private let queue = DispatchQueue(label: "dev.tab2mac.transport.adb", qos: .utility)
    private let lock = NSLock()
    private var tracker: Process?
    private var isMaintaining = false
    private var reversed: Set<String> = []
    private var lastDevices: [AdbDevice] = []
    /// Handed to the Tab2Mac app on every device after `adb reverse` (see `deliverToken`).
    private var token: String?
    private var lastRedelivery: MediaTime?

    public init(executable: URL) {
        self.executable = executable
    }

    /// First adb found in the usual places (ANDROID_HOME, Homebrew, Android Studio, PATH).
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> AdbBridge? {
        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let root = environment[key] { candidates.append("\(root)/platform-tools/adb") }
        }
        candidates += [
            "/opt/homebrew/bin/adb",
            "/opt/homebrew/share/android-commandlinetools/platform-tools/adb",
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb",
            "/usr/local/bin/adb",
        ]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/adb" }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { AdbBridge(executable: URL(fileURLWithPath: $0)) }
    }

    /// Parses `adb devices -l` (and the device lists of `adb track-devices -l`).
    public static func parseDevices(_ output: String) -> [AdbDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line -> AdbDevice? in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 2, !line.hasPrefix("List of devices"), !line.hasPrefix("*") else { return nil }
            var properties: [String: String] = [:]
            for field in fields.dropFirst(2) {
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { properties[pair[0]] = pair[1] }
            }
            return AdbDevice(
                serial: fields[0], state: fields[1], model: properties["model"], product: properties["product"],
                isUSB: properties["usb"] != nil
            )
        }
    }

    public func devices() throws -> [AdbDevice] {
        Self.parseDevices(try run(["devices", "-l"]))
    }

    public func reverse(serial: String, port: UInt16) throws {
        _ = try run(["-s", serial, "reverse", "tcp:\(port)", "tcp:\(port)"])
    }

    /// The broadcast that hands the Tab2Mac app its loopback token. Its receiver requires the
    /// `DUMP` permission, which only the adb shell holds, so no other app can plant a token.
    /// The token itself goes through stdin, never on a command line.
    static let tokenCommand = "read t; am broadcast -f 32 -a dev.tab2mac.action.LOOPBACK_TOKEN -n dev.tab2mac.receiver/dev.tab2mac.receiver.adb.LoopbackTokenReceiver --es token \"$t\""

    public func deliverToken(_ token: String, serial: String) throws {
        _ = try run(["-s", serial, "shell", Self.tokenCommand], input: Data((token + "\n").utf8))
    }

    /// Hands the token to every ready device again (a connection came without it, e.g. the app
    /// was installed after the device appeared). At most every 5 s.
    public func redeliverToken() {
        queue.async { [weak self] in
            guard let self else { return }
            let (token, serials) = self.lock.withLock { () -> (String?, [String]) in
                if let last = self.lastRedelivery, MediaTime.now() - last < .seconds(5) { return (nil, []) }
                self.lastRedelivery = .now()
                return (self.token, self.lastDevices.filter(\.isReady).map(\.serial))
            }
            guard let token else { return }
            for serial in serials { self.deliverTokenLogged(token, serial: serial) }
        }
    }

    private func deliverTokenLogged(_ token: String, serial: String) {
        do {
            try deliverToken(token, serial: serial)
            Log.transport.info("adb.token-delivered serial=\(serial, privacy: .public)")
        } catch {
            Log.transport.error("adb.token-failed serial=\(serial, privacy: .public) reason=\(String(describing: error), privacy: .public)")
        }
    }

    /// Keeps the reverse port forward in place for every authorised device, re-establishing it
    /// when a device reconnects or the adb server restarts (which drops all forwards).
    /// - Parameter token: handed to the Tab2Mac app on each device after the reverse (nil: none).
    public func startMaintainingReverse(port: UInt16, token: String? = nil, onChange: @escaping @Sendable ([AdbDevice]) -> Void) {
        stop()
        lock.withLock {
            isMaintaining = true
            self.token = token
        }
        startTracker(port: port, onChange: onChange, attempt: 0)
    }

    public func stop() {
        let tracker = lock.withLock { () -> Process? in
            isMaintaining = false
            reversed.removeAll()
            lastDevices = []
            defer { self.tracker = nil }
            return self.tracker
        }
        if let tracker, tracker.isRunning { tracker.terminate() }
    }

    private func startTracker(port: UInt16, onChange: @escaping @Sendable ([AdbDevice]) -> Void, attempt: Int) {
        guard lock.withLock({ isMaintaining }) else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["track-devices", "-l"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let parser = OSAllocatedUnfairLock(initialState: AdbTrackParser())
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self else { return }
            for devices in parser.withLock({ $0.feed(data) }) {
                self.queue.async { [weak self] in self?.apply(devices, port: port, onChange: onChange) }
            }
        }
        let started = MediaTime.now()
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            let restart = self.lock.withLock { () -> Bool in
                self.reversed.removeAll()  // a restarted adb server has no forwards
                return self.isMaintaining
            }
            guard restart else { return }
            // Back off while adb keeps failing; start over after a healthy run.
            let next = (MediaTime.now() - started) > .seconds(30) ? 0 : attempt + 1
            let delay = min(30, 1 << min(next, 5))
            Log.transport.info("adb.tracker-exited restart_in_s=\(delay)")
            self.queue.asyncAfter(deadline: .now() + .seconds(delay)) {
                self.startTracker(port: port, onChange: onChange, attempt: next)
            }
        }
        do {
            try process.run()
            lock.withLock { tracker = process }
        } catch {
            Log.transport.error("adb.tracker-failed reason=\(String(describing: error), privacy: .public)")
            queue.asyncAfter(deadline: .now() + .seconds(min(30, 1 << min(attempt + 1, 5)))) { [weak self] in
                self?.startTracker(port: port, onChange: onChange, attempt: attempt + 1)
            }
        }
    }

    private func apply(_ devices: [AdbDevice], port: UInt16, onChange: @Sendable ([AdbDevice]) -> Void) {
        let readySerials = Set(devices.filter(\.isReady).map(\.serial))
        let (needReverse, changed) = lock.withLock { () -> (Set<String>, Bool) in
            reversed.formIntersection(readySerials)
            let changed = devices != lastDevices
            lastDevices = devices
            return (readySerials.subtracting(reversed), changed)
        }
        let token = lock.withLock { self.token }
        for serial in needReverse {
            do {
                try reverse(serial: serial, port: port)
                lock.withLock { _ = reversed.insert(serial) }
                Log.transport.info("adb.reverse serial=\(serial, privacy: .public) port=\(port)")
                if let token { deliverTokenLogged(token, serial: serial) }
            } catch {
                Log.transport.error("adb.reverse-failed serial=\(serial, privacy: .public) reason=\(String(describing: error), privacy: .public)")
            }
        }
        if changed { onChange(devices) }
    }

    public enum AdbError: Error, CustomStringConvertible {
        case failed(arguments: [String], status: Int32, output: String)

        public var description: String {
            switch self {
            case .failed(let arguments, let status, let output): "adb \(arguments.joined(separator: " ")) exited \(status): \(output)"
            }
        }
    }

    private func run(_ arguments: [String], input: Data? = nil) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let stdin = input.map { _ in Pipe() }
        process.standardInput = stdin ?? FileHandle.nullDevice
        try process.run()
        if let stdin, let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw AdbError.failed(arguments: arguments, status: process.terminationStatus, output: output)
        }
        return output
    }
}

/// Incremental parser for `adb track-devices` output: each update is a 4-digit hex length and
/// then that many bytes in `adb devices -l` format (an empty list is `0000`).
public struct AdbTrackParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ data: Data) -> [[AdbDevice]] {
        buffer.append(contentsOf: data)
        var updates: [[AdbDevice]] = []
        while buffer.count >= 4 {
            // Four hex digits of payload length, then the payload.
            let prefix = buffer[0..<4]
            guard prefix.allSatisfy({ Character(Unicode.Scalar($0)).isHexDigit }),
                  let length = Int(String(decoding: prefix, as: UTF8.self), radix: 16) else {
                buffer.removeAll()  // not the expected framing: drop and wait for the next update
                break
            }
            guard buffer.count >= 4 + length else { break }
            updates.append(AdbBridge.parseDevices(String(decoding: buffer[4..<(4 + length)], as: UTF8.self)))
            buffer.removeFirst(4 + length)
        }
        return updates
    }
}
