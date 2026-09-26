import AppKit

// Standard output is often a file when launched via `open --stdout`; make prints appear promptly.
setvbuf(stdout, nil, _IOLBF, 0)

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
application.delegate = delegate
application.run()
