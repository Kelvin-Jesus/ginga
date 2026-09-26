import Testing
@testable import DirectLink

@Suite("CoreWLANWiFi")
struct CoreWLANWiFiTests {
    /// Read-only: the loopback interface has 127.0.0.1, and a missing one has none.
    @Test func findsAnInterfacesIPv4Address() {
        #expect(CoreWLANWiFi.ipv4Address(of: "lo0") == "127.0.0.1")
        #expect(CoreWLANWiFi.ipv4Address(of: "no-such-interface") == nil)
    }
}
