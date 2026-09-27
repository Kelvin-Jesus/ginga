import CoreGraphics
import GingaProtocol
import Testing
@testable import InputInjection

@Suite("KeyboardMapper")
struct KeyboardMapperTests {
    @Test func lettersDigitsAndKeysMapByPosition() {
        let mapper = KeyboardMapper()
        #expect(mapper.virtualKey(forUsage: 0x04) == 0x00)  // A
        #expect(mapper.virtualKey(forUsage: 0x1D) == 0x06)  // Z
        #expect(mapper.virtualKey(forUsage: 0x1E) == 0x12)  // 1
        #expect(mapper.virtualKey(forUsage: 0x27) == 0x1D)  // 0
        #expect(mapper.virtualKey(forUsage: 0x28) == 0x24)  // Return
        #expect(mapper.virtualKey(forUsage: 0x3A) == 0x7A)  // F1
        #expect(mapper.virtualKey(forUsage: 0x45) == 0x6F)  // F12
        #expect(mapper.virtualKey(forUsage: 0x50) == 0x7B)  // ←
        #expect(mapper.virtualKey(forUsage: 0x4C) == 0x75)  // forward delete
        #expect(mapper.virtualKey(forUsage: 0x87) == 0x5E)  // ABNT2 /?
        #expect(mapper.virtualKey(forUsage: 0x64) == 0x0A)  // ISO extra key
        // On a U.S.-family Mac layout that key would type §: it types \ as on the tablet instead.
        #expect(KeyboardMapper(isoKeyTypesBackslash: true).virtualKey(forUsage: 0x64) == 0x2A)
        #expect(KeyboardMapper(isoKeyTypesBackslash: true).virtualKey(forUsage: 0x31) == 0x2A)  // the usual \ key unchanged
        #expect(mapper.virtualKey(forUsage: 0x65) == nil)   // application menu: no Mac key
    }

    @Test func everyLetterAndDigitHasADistinctKey() {
        let mapper = KeyboardMapper()
        let codes = (0x04...0x27).compactMap { mapper.virtualKey(forUsage: UInt16($0)) }
        #expect(codes.count == 36 && Set(codes).count == 36)
    }

    @Test func theCommandKeyFollowsTheSetting() {
        let meta = KeyboardMapper(commandKey: .meta)
        #expect(meta.virtualKey(forUsage: 0xE3) == 0x37)  // ⊞ → ⌘
        #expect(meta.virtualKey(forUsage: 0xE0) == 0x3B)  // Ctrl → ⌃
        #expect(meta.flags(for: [.leftMeta, .leftShift]) == [.maskCommand, .maskShift])
        let control = KeyboardMapper(commandKey: .control)
        #expect(control.virtualKey(forUsage: 0xE0) == 0x37)  // Ctrl → ⌘
        #expect(control.virtualKey(forUsage: 0xE3) == 0x3B)
        #expect(control.flags(for: [.rightControl]) == .maskCommand)
        #expect(control.flags(for: [.leftAlt, .capsLock]) == [.maskAlternate, .maskAlphaShift])
        #expect(KeyboardMapper.isModifier(0xE1) && !KeyboardMapper.isModifier(0x04))
    }
}

@MainActor
@Suite("KeyboardLayout")
struct KeyboardLayoutTests {
    /// Read-only: asks the current layout what a key types. Any Latin layout types a letter for
    /// kVK_ANSI_A, and the ISO key answer doesn't crash whatever the layout.
    @Test func readsTheCurrentLayout() {
        let a = KeyboardLayout.character(forKeyCode: 0x00)
        #expect(a?.count == 1)
        _ = KeyboardLayout.isoKeyTypesSection()
    }
}
