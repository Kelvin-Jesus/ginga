import Foundation
import Testing
@testable import GingaCore

@Suite("AppVersion")
struct AppVersionTests {
    /// The version compiled into ginga and the one in the app bundle must not drift apart.
    @Test func infoPlistAndCompiledVersionAgree() throws {
        let plist = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GingaCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // mac
            .appendingPathComponent("Resources/Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist))
        #expect(info["CFBundleShortVersionString"] as? String == AppVersion.compiled)
    }
}
