import Carbon

enum LayoutManager {

    static func getKeyboardInputSources() -> [TISInputSource] {
        let conditions: CFDictionary = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnabled as String: true as Any,
            kTISPropertyInputSourceIsSelectCapable as String: true as Any
        ] as CFDictionary

        guard let sourceList = TISCreateInputSourceList(conditions, false)?
            .takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sourceList
    }

    static func shortName(for source: TISInputSource) -> String {
        guard let langs = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return "??"
        }
        // swiftlint:disable:next force_cast
        let languages = Unmanaged<CFArray>.fromOpaque(langs).takeUnretainedValue() as! [String]
        return languages.first?.prefix(2).uppercased() ?? "??"
    }

    static func sourceID(for source: TISInputSource) -> String {
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown"
        }
        return Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    }

    static var currentShortName: String {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "??"
        }
        return shortName(for: current)
    }

    /// Switches to the next enabled keyboard input source.
    /// Returns the short name of the new layout, or nil if switching failed.
    @discardableResult
    static func switchToNext() -> String? {
        let sources = getKeyboardInputSources()
        if sources.count < 2 {
            print("⚠️  Less than 2 input sources enabled. Nothing to switch.")
            return nil
        }

        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            print("⚠️  Could not get current input source")
            return nil
        }
        let currentID = sourceID(for: current)

        let currentIndex = sources.firstIndex(where: { sourceID(for: $0) == currentID }) ?? 0
        let nextIndex = (currentIndex + 1) % sources.count
        let nextSource = sources[nextIndex]

        let status = TISSelectInputSource(nextSource)
        let name = shortName(for: nextSource)
        if status == noErr {
            return name
        } else {
            print("❌ TISSelectInputSource failed with status: \(status)")
            return nil
        }
    }

    static func printAvailableSources() {
        let sources = getKeyboardInputSources()
        print("📋 Available keyboard layouts:")
        for (i, source) in sources.enumerated() {
            let name = shortName(for: source)
            let id = sourceID(for: source)
            print("   [\(i)] \(name) — \(id)")
        }
        if sources.count < 2 {
            print("⚠️  Need at least 2 input sources for switching!")
        }
    }
}
