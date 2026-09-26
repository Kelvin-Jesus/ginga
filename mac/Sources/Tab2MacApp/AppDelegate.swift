import AppKit
import DirectLink
import CGVirtualDisplayBackend
import DisplayCapture
import SwiftUI
import Tab2MacCore
import Tab2MacSession
import Tab2MacRuntime
import Tab2MacSecurity
import Tab2MacStreaming
import USBAccessory
import VirtualDisplay

/// How the app was launched. Headless modes exist so that capture can run under the app's own
/// Screen Recording grant (processes started from a terminal are attributed to the terminal).
enum LaunchMode {
    case interactive
    case selfTest
    case captureBenchmark

    init(arguments: [String]) {
        if arguments.contains("--self-test") {
            self = .selfTest
        } else if arguments.contains("--benchmark-capture") {
            self = .captureBenchmark
        } else {
            self = .interactive
        }
    }
}

struct LaunchOptions {
    var configPath: String?
    var reportPath: String?
    var snapshotPath: String?
    var seconds: Double?
    var exerciseLiveChanges = true
    var requestPermission = false
    /// Interactive mode: create the virtual display right after launch.
    var createDisplay = false
    /// Interactive mode: open the debug preview once the display exists.
    var showPreview = false
    /// Interactive mode: accept a tablet over USB right away.
    var serve = false
    /// Interactive mode: keep an animated test pattern on the tablet display.
    var testPattern = false
    /// Interactive mode: start in the menu bar without opening the control panel.
    var background = false
    /// The token loopback (adb) connections must present; generated per launch unless given
    /// (benchmarks pass one to `t2m receive`).
    var loopbackToken: String?

    init(arguments: [String]) {
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), arguments.index(after: index) < arguments.endIndex else { return nil }
            return arguments[arguments.index(after: index)]
        }
        configPath = value("--config")
        reportPath = value("--report")
        snapshotPath = value("--snapshot")
        seconds = value("--seconds").flatMap(Double.init)
        exerciseLiveChanges = !arguments.contains("--no-live-changes")
        requestPermission = arguments.contains("--request-permission")
        createDisplay = arguments.contains("--create-display")
        showPreview = arguments.contains("--show-preview")
        serve = arguments.contains("--serve")
        testPattern = arguments.contains("--test-pattern")
        background = arguments.contains("--background")
        loopbackToken = value("--loopback-token")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let mode = LaunchMode(arguments: CommandLine.arguments)
    private let options = LaunchOptions(arguments: CommandLine.arguments)
    private var model: AppModel?
    private var runtime: Tab2MacRuntime?
    private var controlWindow: NSWindow?
    private var previewController: PreviewWindowController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        switch mode {
        case .interactive:
            setUpInteractive()
        case .selfTest:
            Task { exit(await HeadlessRunner.selfTest(options)) }
        case .captureBenchmark:
            Task { exit(await HeadlessRunner.captureBenchmark(options)) }
        }
    }

    /// Tablets hear GOODBYE "shutdown" right away (and reconnect when the app is back) instead
    /// of waiting for the link to go silent.
    func applicationWillTerminate(_ notification: Notification) {
        runtime?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // keeps running from the menu bar; the virtual display lives as long as the app
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlPanel()
        return true
    }

    // MARK: Interactive UI

    private func setUpInteractive() {
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()

        // Settings given with --config are used for this run only: saving them over the user's own
        // file (or back into the given one) would be a surprise.
        let store = options.configPath == nil ? ConfigurationStore() : nil
        let configuration: Tab2MacConfiguration
        var configurationProblem: String?
        do {
            configuration = try HeadlessRunner.loadConfiguration(path: options.configPath, store: ConfigurationStore())
        } catch {
            // The file stays as it is: the first save keeps it aside instead of overwriting it.
            Log.app.error("app.config-invalid reason=\(String(describing: error), privacy: .public)")
            configurationProblem = "The settings file couldn't be used (\(error)). Running with defaults."
            configuration = Tab2MacConfiguration()
        }

        // The composition (display, capture, streaming, USB, Wi‑Fi, input) is shared with `t2m run`.
        let runtime = Tab2MacRuntime(configuration: configuration, loopbackToken: options.loopbackToken, pairingPresenter: { PairingPrompt.present($0) })
        self.runtime = runtime
        let inputRouter = runtime.inputRouter
        let model = AppModel(session: runtime.session, store: store, configuration: configuration, streamServer: runtime.server)
        model.onInputSettings = { inputRouter.settings = $0 }
        if let configurationProblem { model.report(configurationProblem) }
        self.model = model
        model.accessories = runtime.accessories
        model.wifi = runtime.wifi
        model.direct = runtime.direct
        do {
            try runtime.start(serveUSB: false)
        } catch {
            model.report("Could not start: \(error)")
        }
        let provider = runtime.session.provider

        statusItem = StatusItemController(
            model: model,
            showControlPanel: { [weak self] in self?.showControlPanel() },
            showPreview: { [weak self] in self?.showPreview() }
        )
        if !options.background { showControlPanel() }
        Log.app.info("app.launched backend=\(provider.backendIdentifier, privacy: .public) available=\(provider.backendAvailability().isAvailable)")

        if options.createDisplay {
            Task {
                await model.createDisplay()
                if options.showPreview { showPreview() }
            }
        }
        if options.serve {
            model.setStreaming(true)
        }
        if options.testPattern {
            model.setTestPattern(true)
        }
    }

    private func showControlPanel() {
        guard let model else { return }
        if controlWindow == nil {
            let hosting = NSHostingController(rootView: ControlPanelView(model: model, showPreview: { [weak self] in self?.showPreview() }))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Tab2Mac"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 760))
            window.center()
            controlWindow = window
            model.controlWindow = window
            // Diagnostics refresh only while the panel can actually be seen.
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak model, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    model?.setObserving(window, visible: window.occlusionState.contains(.visible))
                }
            }
        }
        controlWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showPreview() {
        guard let model, model.active != nil else { return }
        if previewController == nil {
            previewController = PreviewWindowController(model: model)
        }
        previewController?.present()
    }
}

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tab2Mac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Tab2Mac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Tab2Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return main
    }
}
