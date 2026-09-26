import os

/// Structured, per-layer unified logging.
///
/// Stream everything with:
///     log stream --level debug --predicate 'subsystem == "dev.tab2mac"'
/// Messages use `event.name key=value …` so they are easy to grep and parse.
public enum Log {
    public static let subsystem = "dev.tab2mac"

    public static let virtualDisplay = Logger(subsystem: subsystem, category: "virtual-display")
    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let session = Logger(subsystem: subsystem, category: "session")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let benchmark = Logger(subsystem: subsystem, category: "benchmark")
}
