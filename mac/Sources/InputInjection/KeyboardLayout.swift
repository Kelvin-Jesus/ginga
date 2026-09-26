import Carbon

/// Questions about the Mac's current keyboard layout (Text Input Sources). Main thread only, as
/// TIS requires.
@MainActor
public enum KeyboardLayout {
    /// Whether the current layout gives the ISO key left of Z (kVK_ISO_Section) `§`: layouts made
    /// for ANSI keyboards (U.S., U.S. International, …) do; ISO layouts (German, Spanish,
    /// Brazilian…) give it their own character (`<`, `\\`…).
    public static func isoKeyTypesSection() -> Bool {
        character(forKeyCode: UInt16(kVK_ISO_Section)) == "§"
    }

    /// What a key types without modifiers under the current layout (dead keys yield nothing).
    static func character(forKeyCode code: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}
