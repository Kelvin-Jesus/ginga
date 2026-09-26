import Testing

/// Suites that drive the Objective‑C fakes share their class-level state (instance counters,
/// failure switches). `.serialized` only orders tests *within* a suite, so every such suite is
/// nested here to keep them from running concurrently with each other.
@Suite("Private API fakes", .serialized)
enum PrivateAPIFakeSuites {}
