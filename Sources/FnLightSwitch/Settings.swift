import Foundation

/// User-toggleable feature flags persisted to UserDefaults. Defaults are
/// registered at app launch in `main.swift` so the first-run state is the
/// expected "everything on".
enum Settings {
    private static let languageSwitchKey = "languageSwitchEnabled"

    /// Default values registered at launch — `register(defaults:)` only
    /// applies them when no value has been set yet.
    static var defaults: [String: Any] {
        [
            languageSwitchKey: true
        ]
    }

    /// Whether tapping Fn switches the keyboard layout. When false, the Fn
    /// tap detector still runs (we keep accessibility wired) but the
    /// callback short-circuits.
    static var languageSwitchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: languageSwitchKey) }
        set { UserDefaults.standard.set(newValue, forKey: languageSwitchKey) }
    }
}
