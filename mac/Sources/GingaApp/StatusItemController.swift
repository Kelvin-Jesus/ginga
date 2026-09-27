import AppKit
import GingaSession

/// The menu bar (flows.md "Barra de menus"): mark A, with a dot for Conectado (success) or Erro
/// (danger), and a menu that follows the state. Rebuilt only when opened; the icon changes only
/// when the model does (no timers: the "searching" star doesn't blink, to spend nothing).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let showControlPanel: () -> Void
    private let showSettings: () -> Void
    private var shownState: StatusOrbit.State?

    init(model: AppModel, showControlPanel: @escaping () -> Void, showSettings: @escaping () -> Void) {
        self.model = model
        self.showControlPanel = showControlPanel
        self.showSettings = showSettings
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.setAccessibilityLabel("Ginga")
        observe()
    }

    /// Follows the connection state through Observation: the icon updates on change only.
    private func observe() {
        let state = withObservationTracking { model.connectionState.state } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observe() }
        }
        guard state != shownState else { return }
        shownState = state
        item.button?.image = Self.icon(dot: Self.dotColor(for: state))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = model.connectionState
        switch status.state {
        case .off:
            menu.addItem(disabled(tr("Ginga está desligado", "Ginga is off")))
            menu.addItem(action(tr("Aceitar tablets", "Accept tablets")) { [model] in
                model.setWiFi(true)
                model.setDirectUSB(true)
            })
        case .searching, .pairing:
            menu.addItem(disabled(status.text))
            for tablet in model.tablets {
                menu.addItem(disabled("  \(tablet.name) · \(tablet.meta)"))
            }
            menu.addItem(action(tr("Parar", "Stop")) { [model] in
                model.setWiFi(false)
                model.setDirectUSB(false)
                if model.isStreamingEnabled { model.setStreaming(false) }
            })
        case .connected, .paused:
            let name = model.tablets.first { $0.meta.contains("·") && !$0.meta.hasPrefix(tr("pareado", "paired")) }?.name
            menu.addItem(disabled([name, status.text].compactMap { $0 }.joined(separator: " · ")))
            if model.active != nil {
                menu.addItem(action(tr("Remover display", "Remove display")) { [model] in Task { await model.removeDisplay() } })
            }
            menu.addItem(action(tr("Ajustes de Telas…", "Displays Settings…")) { [model] in model.openDisplaysSettings() })
        case .error:
            menu.addItem(disabled(status.text))
            menu.addItem(action(tr("Tentar de novo", "Try again")) { [model] in
                model.report(nil)
                if model.active == nil { Task { await model.createDisplay() } }
            })
        }
        if model.active == nil, status.state != .off {
            menu.addItem(action(tr("Criar display", "Create display")) { [model] in Task { await model.createDisplay() } })
        }
        menu.addItem(.separator())
        menu.addItem(action(tr("Abrir Ginga…", "Open Ginga…"), showControlPanel))
        menu.addItem(action(tr("Ajustes…", "Settings…"), showSettings))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: tr("Sair do Ginga", "Quit Ginga"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private static func dotColor(for state: StatusOrbit.State) -> NSColor? {
        switch state {
        case .connected: NSColor(srgbRed: 0.31, green: 0.816, blue: 0.557, alpha: 1)  // success (dark)
        case .error: NSColor(srgbRed: 0.941, green: 0.455, blue: 0.455, alpha: 1)  // danger (dark)
        default: nil
        }
    }

    /// Mark A drawn in the menu bar's text color; without a dot it's a template image.
    private static func icon(dot: NSColor?) -> NSImage {
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: true) { rect in
            let s = rect.height / 120 * 1.15
            let transform = NSAffineTransform()
            transform.translateX(by: -2, yBy: -3)
            transform.scale(by: s)
            transform.translateX(by: 1.2, yBy: 6.4)
            transform.concat()
            let ink = dot == nil ? NSColor.black : NSColor.labelColor
            let outline = NSBezierPath(roundedRect: NSRect(x: 10, y: 22, width: 66, height: 48), xRadius: 9, yRadius: 9)
            outline.lineWidth = 9
            ink.setStroke()
            outline.stroke()
            let tablet = NSBezierPath(roundedRect: NSRect(x: 50, y: 48, width: 58, height: 42), xRadius: 9, yRadius: 9)
            let rotate = NSAffineTransform()
            rotate.translateX(by: 78, yBy: 70)
            rotate.rotate(byDegrees: -10)
            rotate.translateX(by: -78, yBy: -70)
            tablet.transform(using: rotate as AffineTransform)
            ink.setFill()
            tablet.fill()
            if let dot {
                NSAffineTransform().concat()
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: 88, y: 0, width: 30, height: 30)).fill()
            }
            return true
        }
        image.isTemplate = dot == nil
        return image
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        ClosureMenuItem(title: title, handler: handler)
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func invoke() {
        handler()
    }
}
