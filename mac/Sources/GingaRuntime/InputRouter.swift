import Foundation
import InputInjection
import GingaCore
import GingaProtocol
import GingaSession
import VirtualDisplay

/// Receiver input → gestures → CGEvents on the virtual display (M5).
@MainActor
public final class InputRouter {
    private var interpreter: InputInterpreter?
    private let injector = CGEventInjector()
    private var warnedAboutPermission = false
    /// From `input` in the configuration; applies to the next event.
    public var settings = InputSettings() {
        didSet { interpreter?.touchMode = settings.touch == .gestures ? .gestures : .pointer }
    }

    public init() {}

    public func handle(_ input: InputMessage, display: ActiveVirtualDisplay) {
        // Keep the gesture state across events; only the target rectangle follows the display.
        var interpreter = self.interpreter ?? InputInterpreter(bounds: display.bounds)
        interpreter.bounds = display.bounds
        interpreter.touchMode = settings.touch == .gestures ? .gestures : .pointer
        let events = interpreter.interpret(input)
        self.interpreter = interpreter

        guard CGEventInjector.hasPermission else {
            if !warnedAboutPermission {
                warnedAboutPermission = true
                Log.input.error("input.permission-missing — grant Ginga access in System Settings › Privacy & Security › Accessibility")
            }
            return
        }
        injector.post(events)
    }

    public func handleKey(_ key: KeyMessage) {
        guard checkPermission() else { return }
        let mapper = KeyboardMapper(
            commandKey: settings.commandKey == .control ? .control : .meta,
            // Only this rare key needs the layout; asked on its press and release (main thread).
            isoKeyTypesBackslash: key.usage == KeyboardMapper.isoKeyUsage && KeyboardLayout.isoKeyTypesSection()
        )
        injector.postKey(key, mapper: mapper)
    }

    private func checkPermission() -> Bool {
        guard CGEventInjector.hasPermission else {
            if !warnedAboutPermission {
                warnedAboutPermission = true
                Log.input.error("input.permission-missing — grant Ginga access in System Settings › Privacy & Security › Accessibility")
            }
            return false
        }
        return true
    }

    /// The receiver went away: release whatever its gesture still holds (a button mid-drag, an
    /// open scroll), so the Mac isn't left with a stuck button.
    public func reset() {
        injector.releaseKeys()
        guard var interpreter else { return }
        let events = interpreter.reset()
        self.interpreter = nil
        guard !events.isEmpty, CGEventInjector.hasPermission else { return }
        injector.post(events)
    }
}
