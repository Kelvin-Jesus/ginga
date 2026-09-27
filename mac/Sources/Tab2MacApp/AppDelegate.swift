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
    private var settingsWindow: NSWindow?
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
        let runtime = Tab2MacRuntime(configuration: configuration, loopbackToken: options.loopbackToken, pairingPresenter: { [weak self] in self?.presentPairing($0) })
        self.runtime = runtime
        let inputRouter = runtime.inputRouter
        let model = AppModel(session: runtime.session, store: store, configuration: configuration, streamServer: runtime.server)
        model.onInputSettings = { inputRouter.settings = $0 }
        if let configurationProblem { model.report(configurationProblem) }
        self.model = model
        model.accessories = runtime.accessories
        model.wifi = runtime.wifi
        model.direct = runtime.direct
        if let index = CommandLine.arguments.firstIndex(of: "--render-ui"), CommandLine.arguments.indices.contains(index + 1) {
            UIRenderer.render(model: model, to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        do {
            try runtime.start(serveUSB: false)
        } catch {
            model.report("Could not start: \(error)")
        }
        let provider = runtime.session.provider

        statusItem = StatusItemController(
            model: model,
            showControlPanel: { [weak self] in self?.showControlPanel() },
            showSettings: { [weak self] in self?.showSettings() }
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
            let root = ThemedRoot(model: model) { [weak self] in
                MainWindowView(model: model, showSettings: { self?.showSettings() })
            }
            let window = Self.makeWindow(root, title: "Ginga", size: NSSize(width: 480, height: 640))
            controlWindow = window
            model.controlWindow = window
            // Orbits move and diagnostics refresh only while the window can actually be seen.
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak model, weak window] _ in
                MainActor.assumeIsolated {
                    guard let window else { return }
                    model?.mainWindowVisibilityChanged(window, visible: window.occlusionState.contains(.visible))
                }
            }
        }
        controlWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showSettings() {
        guard let model else { return }
        if settingsWindow == nil {
            let root = ThemedRoot(model: model) { [weak self] in
                SettingsView(model: model, showPreview: { self?.showPreview() })
            }
            settingsWindow = Self.makeWindow(root, title: tr("Ajustes do Ginga", "Ginga Settings"), size: NSSize(width: 540, height: 720))
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// A tablet asks to pair: the question is a sheet on the main window (shown if needed). It
    /// goes away by itself when the tablet leaves, declines or times out.
    private func presentPairing(_ request: PairingRequest) {
        guard let model, !request.isEnded else { return }
        showControlPanel()
        model.pairingRequest = request
        request.onEnd { [weak model] in
            if model?.pairingRequest === request { model?.pairingRequest = nil }
        }
    }

    private static func makeWindow<Root: View>(_ root: Root, title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.center()
        return window
    }

    private func showPreview() {
        guard let model, model.active != nil else { return }
        if previewController == nil {
            previewController = PreviewWindowController(model: model)
        }
        previewController?.present()
    }
}

/// A window's content under the Ginga theme; motion only while the main window is visible.
private struct ThemedRoot<Content: View>: View {
    let model: AppModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        GingaThemed(animates: model.mainWindowVisible) { content() }
    }
}

enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("Sobre o Ginga", "About Ginga"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Ocultar Ginga", "Hide Ginga"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Sair do Ginga", "Quit Ginga"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: tr("Janela", "Window"))
        windowMenu.addItem(withTitle: tr("Minimizar", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: tr("Fechar", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        return main
    }
}
