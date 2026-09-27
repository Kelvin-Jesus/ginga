import Foundation
import GingaCore
import GingaSession
import VirtualDisplay

/// Minimal `command --option value --flag` parser (no third-party dependency).
struct Arguments {
    static let flagNames: Set<String> = ["json", "portrait", "standard", "no-capture", "no-live-changes", "help", "synthetic", "no-adb", "decode", "sweep", "realtime", "power-efficient"]

    var command: String?
    var options: [String: String] = [:]
    var flags: Set<String> = []

    init(_ raw: [String]) throws {
        var index = raw.startIndex
        while index < raw.endIndex {
            let token = raw[index]
            if token.hasPrefix("--") {
                let name = String(token.dropFirst(2))
                if Self.flagNames.contains(name) {
                    flags.insert(name)
                } else {
                    let next = raw.index(after: index)
                    guard next < raw.endIndex, !raw[next].hasPrefix("--") else {
                        throw CLIError.usage("option --\(name) needs a value")
                    }
                    options[name] = raw[next]
                    index = next
                }
            } else if command == nil {
                command = token
            } else {
                throw CLIError.usage("unexpected argument '\(token)'")
            }
            index = raw.index(after: index)
        }
    }

    func double(_ name: String) throws -> Double? {
        guard let value = options[name] else { return nil }
        guard let number = Double(value) else { throw CLIError.usage("--\(name) expects a number, got '\(value)'") }
        return number
    }

    /// Builds the configuration from `--config`, `--profile` and the display overrides.
    func configuration() throws -> GingaConfiguration {
        var configuration: GingaConfiguration
        if let path = options["config"] {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            configuration = try JSONDecoder().decode(GingaConfiguration.self, from: Data(contentsOf: url))
        } else if let id = options["profile"] {
            guard let profile = DeviceProfile.named(id) else {
                throw CLIError.usage("unknown profile '\(id)'; known: \(DeviceProfile.all.map(\.id).joined(separator: ", "))")
            }
            configuration = GingaConfiguration(display: profile.configuration())
        } else {
            configuration = GingaConfiguration()
        }

        if let value = options["resolution"] {
            let parts = value.lowercased().split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { throw CLIError.usage("--resolution expects WxH, e.g. 1440x900") }
            configuration.display.resolution = PointSize(width: parts[0], height: parts[1])
        }
        if let refresh = try double("refresh") { configuration.display.refreshRate = refresh }
        if flags.contains("portrait") { configuration.display.orientation = .portrait }
        if flags.contains("standard") { configuration.display.hiDPI = false }
        if let value = options["position"] {
            let parts = value.split(separator: ":").map(String.init)
            guard let placement = DisplayArrangement.Placement(rawValue: parts[0]) else {
                throw CLIError.usage("--position expects automatic|left|right|above|below[:start|center|end]")
            }
            let alignment = parts.count > 1 ? DisplayArrangement.Alignment(rawValue: parts[1]) : .start
            guard let alignment else { throw CLIError.usage("alignment must be start, center or end") }
            configuration.display.arrangement = DisplayArrangement(placement: placement, alignment: alignment)
        }
        try configuration.validate()
        return configuration
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failed(String)

    var description: String {
        switch self {
        case .usage(let message): "usage error: \(message)"
        case .failed(let message): message
        }
    }
}
