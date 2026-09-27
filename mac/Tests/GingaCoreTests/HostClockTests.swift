import Testing
@testable import GingaCore

@Suite("HostTimebase")
struct HostTimebaseTests {
    /// Apple Silicon reports a 125/3 timebase: mach ticks run at 24 MHz, not in nanoseconds.
    let appleSilicon = HostTimebase(numer: 125, denom: 3)

    @Test func convertsAppleSiliconTicksToNanoseconds() {
        #expect(appleSilicon.nanoseconds(fromTicks: 24_000_000) == 1_000_000_000)
        #expect(appleSilicon.nanoseconds(fromTicks: 3) == 125)
        #expect(appleSilicon.nanoseconds(fromTicks: 0) == 0)
    }

    @Test func identityTimebaseIsPassThrough() {
        let identity = HostTimebase(numer: 1, denom: 1)
        #expect(identity.nanoseconds(fromTicks: 123_456_789) == 123_456_789)
        #expect(identity.ticks(fromNanoseconds: 42) == 42)
    }

    @Test func convertsNanosecondsBackToTicks() {
        #expect(appleSilicon.ticks(fromNanoseconds: 1_000_000_000) == 24_000_000)
        #expect(appleSilicon.ticks(fromNanoseconds: 125) == 3)
    }

    @Test func largeTickCountsDoNotOverflowIntermediateProducts() {
        // ticks * 125 overflows UInt64 here; the conversion must use full-width arithmetic.
        let ticks: UInt64 = 1 << 58
        // floor(ticks * 125 / 3), computed without overflow as 125q + floor(125r / 3) where ticks = 3q + r.
        let expected = (ticks / 3) * 125 + ((ticks % 3) * 125) / 3
        #expect(appleSilicon.nanoseconds(fromTicks: ticks) == expected)
    }

    @Test func currentTimebaseIsValid() {
        #expect(HostTimebase.current.numer > 0)
        #expect(HostTimebase.current.denom > 0)
    }
}

@Suite("MediaTime")
struct MediaTimeTests {
    @Test func subtractionYieldsSignedDuration() {
        let early = MediaTime(nanoseconds: 1_000)
        let late = MediaTime(nanoseconds: 3_500)
        #expect(late - early == .nanoseconds(2_500))
        #expect(early - late == .nanoseconds(-2_500))
    }

    @Test func nowIsMonotonic() {
        let first = MediaTime.now()
        let second = MediaTime.now()
        #expect(second >= first)
    }

    @Test func initialisesFromHostTicks() {
        let time = MediaTime(hostTicks: 24_000_000, timebase: HostTimebase(numer: 125, denom: 3))
        #expect(time.nanoseconds == 1_000_000_000)
    }

    @Test func advancesByDuration() {
        #expect(MediaTime(nanoseconds: 10).advanced(by: .nanoseconds(5)) == MediaTime(nanoseconds: 15))
        #expect(MediaTime(nanoseconds: 10).advanced(by: .nanoseconds(-5)) == MediaTime(nanoseconds: 5))
    }

    @Test func durationConvertsToFractionalMilliseconds() {
        #expect(Duration.microseconds(1_500).inMilliseconds == 1.5)
        #expect(Duration.seconds(2).inMilliseconds == 2_000)
        #expect(Duration.nanoseconds(-250_000).inMilliseconds == -0.25)
    }
}
