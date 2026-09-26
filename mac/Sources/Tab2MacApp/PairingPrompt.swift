import AppKit
import Tab2MacStreaming

/// Asks the Mac's user to compare the pairing code with the tablet's (numeric comparison).
@MainActor
enum PairingPrompt {
    static func present(_ request: PairingRequest) {
        // Return right away: the connection waits for `respond`, and nothing else should block.
        DispatchQueue.main.async {
            guard !request.isEnded else { return }
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "Pair with “\(request.tabletName)”?"
            let code = request.code.prefix(3) + " " + request.code.suffix(3)
            alert.informativeText = "Make sure the tablet shows the same code:\n\n\(code)\n\nOnly pair tablets you own. A paired tablet can show this Mac's extended display and control it with touch and S Pen."
            alert.addButton(withTitle: "Pair")
            alert.addButton(withTitle: "Don’t Pair")
            // The tablet left, declined or timed out: the question is moot, so the alert goes away.
            request.onEnd { NSApp.abortModal() }
            let response = alert.runModal()
            if response != .abort { request.respond(response == .alertFirstButtonReturn) }
        }
    }
}
