import AppKit
import CGVirtualDisplayBackend
import DisplayCapture
import Foundation
import GingaCore
import GingaSession
import VirtualDisplay

/// Non-interactive modes of the app bundle (so capture runs under the app's own TCC grant):
///
///     open -W --stdout /tmp/ginga.txt build/Ginga.app --args --self-test
///     open -W --stdout /tmp/ginga.txt build/Ginga.app --args --benchmark-capture --seconds 10
@MainActor
enum HeadlessRunner {
    static var reportsDirectory: URL {
        ConfigurationStore.defaultURL.deletingLastPathComponent().appendingPathComponent("reports")
    }

    static func loadConfiguration(path: String?, store: ConfigurationStore) throws -> GingaConfiguration {
        guard let path else { return try store.load() }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let configuration = try JSONDecoder().decode(GingaConfiguration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }

    static func selfTest(_ options: LaunchOptions) async -> Int32 {
        NSApp.setActivationPolicy(.accessory)
        if options.requestPermission, !ScreenCapturePermission.isGranted {
            ScreenCapturePermission.request()
        }
        let configuration: GingaConfiguration
        do {
            configuration = try loadConfiguration(path: options.configPath, store: ConfigurationStore())
        } catch {
            print("self-test: invalid configuration: \(error)")
            return 2
        }
        let stamp = timestamp()
        let snapshotURL = options.snapshotPath.map(expand) ?? reportsDirectory.appendingPathComponent("self-test-\(stamp).png")
        let verifier = M1Verifier(provider: VirtualDisplayProvider(backend: CGVirtualDisplayBackend()), capture: ScreenCaptureKitSource())
        let report = await verifier.run(M1Verifier.Options(
            configuration: configuration.display,
            captureSettings: configuration.capture,
            includeCapture: true,
            captureSeconds: options.seconds ?? 2,
            exerciseLiveChanges: options.exerciseLiveChanges,
            snapshotURL: snapshotURL
        ))
        print(report.summary)
        let reportURL = options.reportPath.map(expand) ?? reportsDirectory.appendingPathComponent("self-test-\(stamp).json")
        write(report, to: reportURL)
        return report.passed ? 0 : 1
    }

    static func captureBenchmark(_ options: LaunchOptions) async -> Int32 {
        NSApp.setActivationPolicy(.accessory)
        let configuration: GingaConfiguration
        do {
            configuration = try loadConfiguration(path: options.configPath, store: ConfigurationStore())
        } catch {
            print("benchmark: invalid configuration: \(error)")
            return 2
        }
        let benchmark = CaptureBenchmark(provider: VirtualDisplayProvider(backend: CGVirtualDisplayBackend()), capture: ScreenCaptureKitSource())
        do {
            let report = try await benchmark.run(configuration: configuration, captureSeconds: options.seconds ?? 10)
            print(report.summary)
            write(report, to: options.reportPath.map(expand) ?? reportsDirectory.appendingPathComponent("capture-benchmark-\(timestamp()).json"))
            return 0
        } catch {
            print("benchmark failed: \(error)")
            return 1
        }
    }

    private static func write(_ value: some Encodable, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: url, options: .atomic)
            print("report: \(url.path)")
        } catch {
            print("could not write report to \(url.path): \(error)")
        }
    }

    private static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
