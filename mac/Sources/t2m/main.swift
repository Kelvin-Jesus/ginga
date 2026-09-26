import AppKit
import Foundation

// Line-buffer stdout so progress shows up promptly when redirected to a file.
setvbuf(stdout, nil, _IOLBF, 0)

// AppKit's event loop must run: CoreGraphics only refreshes a new display's mode list and
// NSScreen only learns about it while events are being processed.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let rawArguments = Array(CommandLine.arguments.dropFirst())
Task { @MainActor in
    let code: Int32
    do {
        code = try await Commands.run(try Arguments(rawArguments))
    } catch {
        FileHandle.standardError.write(Data("t2m: \(error)\n".utf8))
        code = 1
    }
    exit(code)
}
application.run()
