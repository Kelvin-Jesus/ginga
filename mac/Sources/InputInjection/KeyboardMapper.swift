import CoreGraphics
import Tab2MacProtocol

/// Maps the tablet's keyboard (USB HID usages, PROTOCOL.md §3.3c) to macOS virtual key codes and
/// modifier flags. Pure, so the whole table is unit-tested. The Mac's own keyboard layout then
/// applies, as for any keyboard plugged into it.
public struct KeyboardMapper: Sendable {
    /// Which key of a PC-style keyboard (Samsung's covers) acts as ⌘.
    public enum CommandKey: String, Codable, Sendable, CaseIterable {
        /// ⊞/Samsung key → ⌘, Alt → ⌥, Ctrl → ⌃: what macOS does for a PC keyboard (default).
        case meta
        /// Ctrl → ⌘ (Ctrl+C copies), ⊞/Samsung key → ⌃.
        case control
    }

    public var commandKey: CommandKey
    /// The extra key left of Z on ISO keyboards (HID 0x64) types `\ |` instead of its own key.
    /// Set when the Mac's layout is one made for ANSI keyboards (U.S., U.S. International), which
    /// gives that key `§ ±`; Android (Samsung's key layout), Windows and Linux type `\ |` there
    /// with a US layout, so that is what the keyboard's owner expects.
    public var isoKeyTypesBackslash: Bool

    public init(commandKey: CommandKey = .meta, isoKeyTypesBackslash: Bool = false) {
        self.commandKey = commandKey
        self.isoKeyTypesBackslash = isoKeyTypesBackslash
    }

    /// HID usage of the ISO key left of Z ("Non-US \ and |").
    public static let isoKeyUsage: UInt16 = 0x64

    /// The virtual key for a usage, or nil for keys macOS has no equivalent for.
    public func virtualKey(forUsage usage: UInt16) -> CGKeyCode? {
        if let modifier = modifierKey(forUsage: usage) { return modifier }
        if usage == Self.isoKeyUsage, isoKeyTypesBackslash { return 0x2A }  // kVK_ANSI_Backslash
        return Self.keys[usage]
    }

    /// Whether the usage is a modifier (sent to macOS as a flags change, not a key press).
    public static func isModifier(_ usage: UInt16) -> Bool { (0xE0...0xE7).contains(usage) }

    public func flags(for modifiers: KeyMessage.Modifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        let control = modifiers.contains(.leftControl) || modifiers.contains(.rightControl)
        let meta = modifiers.contains(.leftMeta) || modifiers.contains(.rightMeta)
        if modifiers.contains(.leftShift) || modifiers.contains(.rightShift) { flags.insert(.maskShift) }
        if modifiers.contains(.leftAlt) || modifiers.contains(.rightAlt) { flags.insert(.maskAlternate) }
        switch commandKey {
        case .meta:
            if meta { flags.insert(.maskCommand) }
            if control { flags.insert(.maskControl) }
        case .control:
            if control { flags.insert(.maskCommand) }
            if meta { flags.insert(.maskControl) }
        }
        if modifiers.contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }

    private func modifierKey(forUsage usage: UInt16) -> CGKeyCode? {
        let command: (left: CGKeyCode, right: CGKeyCode) = (0x37, 0x36)
        let control: (left: CGKeyCode, right: CGKeyCode) = (0x3B, 0x3E)
        let (ctrlKeys, metaKeys) = commandKey == .meta ? (control, command) : (command, control)
        switch usage {
        case 0xE0: return ctrlKeys.left
        case 0xE1: return 0x38  // shift
        case 0xE2: return 0x3A  // option
        case 0xE3: return metaKeys.left
        case 0xE4: return ctrlKeys.right
        case 0xE5: return 0x3C  // right shift
        case 0xE6: return 0x3D  // right option
        case 0xE7: return metaKeys.right
        default: return nil
        }
    }

    /// HID Keyboard/Keypad page → kVK_* (Carbon Events.h), by physical position.
    static let keys: [UInt16: CGKeyCode] = {
        var map: [UInt16: CGKeyCode] = [:]
        let letters: [CGKeyCode] = [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                                    0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]  // A…Z
        for (index, code) in letters.enumerated() { map[UInt16(0x04 + index)] = code }
        let digits: [CGKeyCode] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]  // 1…9, 0
        for (index, code) in digits.enumerated() { map[UInt16(0x1E + index)] = code }
        let functionKeys: [CGKeyCode] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]  // F1…F12
        for (index, code) in functionKeys.enumerated() { map[UInt16(0x3A + index)] = code }
        let moreFunctionKeys: [CGKeyCode] = [0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A]  // F13…F20
        for (index, code) in moreFunctionKeys.enumerated() { map[UInt16(0x68 + index)] = code }
        let keypadDigits: [CGKeyCode] = [0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C]  // keypad 1…9
        for (index, code) in keypadDigits.enumerated() { map[UInt16(0x59 + index)] = code }
        let rest: [UInt16: CGKeyCode] = [
            0x28: 0x24, 0x29: 0x35, 0x2A: 0x33, 0x2B: 0x30, 0x2C: 0x31,  // return, escape, backspace, tab, space
            0x2D: 0x1B, 0x2E: 0x18, 0x2F: 0x21, 0x30: 0x1E, 0x31: 0x2A,  // - = [ ] \\
            0x32: 0x2A, 0x33: 0x29, 0x34: 0x27, 0x35: 0x32, 0x36: 0x2B,  // non-US #, ; ' ` ,
            0x37: 0x2F, 0x38: 0x2C, 0x39: 0x39,                          // . / caps lock
            0x46: 0x69, 0x47: 0x6B, 0x48: 0x71,                          // print screen, scroll lock, pause → F13–F15
            0x49: 0x72, 0x4A: 0x73, 0x4B: 0x74, 0x4C: 0x75, 0x4D: 0x77, 0x4E: 0x79,  // insert(help) home pgup del end pgdn
            0x4F: 0x7C, 0x50: 0x7B, 0x51: 0x7D, 0x52: 0x7E,              // → ← ↓ ↑
            0x53: 0x47, 0x54: 0x4B, 0x55: 0x43, 0x56: 0x4E, 0x57: 0x45, 0x58: 0x4C,  // num lock(clear) / * - + enter
            0x62: 0x52, 0x63: 0x41, 0x67: 0x51, 0x85: 0x5F,              // keypad 0 . = ,
            0x64: 0x0A,                                                  // non-US backslash (ISO §, ABNT2 \\|)
            0x87: 0x5E, 0x89: 0x5D,                                      // International1 (ABNT2 /?, JIS ろ), International3 (¥)
            0x7F: 0x4A, 0x80: 0x48, 0x81: 0x49,                          // mute, volume up, volume down
        ]
        map.merge(rest) { _, new in new }
        return map
    }()
}
