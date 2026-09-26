import AppKit
import Tab2MacSession

/// Menu-bar entry: status at a glance plus connect/disconnect-style actions.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let showControlPanel: () -> Void
    private let showPreview: () -> Void

    init(model: AppModel, showControlPanel: @escaping () -> Void, showPreview: @escaping () -> Void) {
        self.model = model
        self.showControlPanel = showControlPanel
        self.showPreview = showPreview
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Tab2Mac")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabled(model.displayStatus))
        menu.addItem(disabled("Capture: \(model.captureStatus)"))
        menu.addItem(disabled("Tablet: \(model.tabletStatus)"))
        menu.addItem(.separator())
        let streamingItem = action(model.isStreamingEnabled ? "Stop Accepting the Tablet" : "Accept the Tablet over USB") { [model] in
            model.setStreaming(!model.isStreamingEnabled)
        }
        menu.addItem(streamingItem)
        if model.active == nil {
            menu.addItem(action("Create Display") { [model] in Task { await model.createDisplay() } })
        } else {
            menu.addItem(action("Remove Display") { [model] in Task { await model.removeDisplay() } })
            menu.addItem(action("Show Debug Preview", showPreview))
        }
        menu.addItem(action("Control Panel…", showControlPanel))
        menu.addItem(action("Displays Settings…") { [model] in model.openDisplaysSettings() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tab2Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        return item
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
