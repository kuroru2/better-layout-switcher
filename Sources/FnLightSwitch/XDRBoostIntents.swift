import AppIntents
import Foundation

/// macOS Shortcuts integration for XDR Boost.
///
/// Each `AppIntent` here shows up in Shortcuts.app as an action under
/// "FnLightSwitch". Users can wire them into Shortcuts of their own
/// (e.g., bind to a hotkey via Shortcuts, trigger via Stream Deck,
/// chain with other automations).

private enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case controllerUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .controllerUnavailable: return "FnLightSwitch is not running."
        }
    }
}

private func requireController() throws -> XDRBoostController {
    guard let c = XDRBoostController.shared else { throw IntentError.controllerUnavailable }
    return c
}

@available(macOS 13.0, *)
struct ToggleXDRBoostIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle XDR Boost"
    static var description = IntentDescription("Turn the XDR Boost on or off.")

    func perform() async throws -> some IntentResult {
        let c = try requireController()
        c.setEnabled(!c.isEnabled)
        return .result()
    }
}

@available(macOS 13.0, *)
struct EnableXDRBoostIntent: AppIntent {
    static var title: LocalizedStringResource = "Enable XDR Boost"
    static var description = IntentDescription("Turn the XDR Boost on.")

    func perform() async throws -> some IntentResult {
        try requireController().setEnabled(true)
        return .result()
    }
}

@available(macOS 13.0, *)
struct DisableXDRBoostIntent: AppIntent {
    static var title: LocalizedStringResource = "Disable XDR Boost"
    static var description = IntentDescription("Turn the XDR Boost off.")

    func perform() async throws -> some IntentResult {
        try requireController().setEnabled(false)
        return .result()
    }
}

@available(macOS 13.0, *)
struct SetXDRBoostLevelIntent: AppIntent {
    static var title: LocalizedStringResource = "Set XDR Boost Level"
    static var description = IntentDescription(
        "Set the XDR Boost level (1.0 = no boost, 2.0 = maximum)."
    )

    @Parameter(
        title: "Level",
        description: "Brightness boost factor",
        controlStyle: .slider,
        inclusiveRange: (1.0, 2.0)
    )
    var level: Double

    func perform() async throws -> some IntentResult {
        let c = try requireController()
        if !c.isEnabled { c.setEnabled(true) }
        c.setLevel(level)
        return .result()
    }
}

@available(macOS 13.0, *)
struct IncreaseXDRBoostIntent: AppIntent {
    static var title: LocalizedStringResource = "Increase XDR Boost"
    static var description = IntentDescription("Step the boost level up by 0.1.")

    func perform() async throws -> some IntentResult {
        let c = try requireController()
        if !c.isEnabled { c.setEnabled(true) }
        c.setLevel(c.level + 0.1)
        return .result()
    }
}

@available(macOS 13.0, *)
struct DecreaseXDRBoostIntent: AppIntent {
    static var title: LocalizedStringResource = "Decrease XDR Boost"
    static var description = IntentDescription("Step the boost level down by 0.1.")

    func perform() async throws -> some IntentResult {
        let c = try requireController()
        c.setLevel(c.level - 0.1)
        return .result()
    }
}

/// Pre-canned Shortcuts that appear automatically in the Shortcuts app once
/// FnLightSwitch has been launched at least once.
@available(macOS 13.0, *)
struct FnLightSwitchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleXDRBoostIntent(),
            phrases: ["Toggle XDR Boost in \(.applicationName)"],
            shortTitle: "Toggle XDR Boost",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: IncreaseXDRBoostIntent(),
            phrases: ["Increase XDR Boost in \(.applicationName)"],
            shortTitle: "Increase XDR Boost",
            systemImageName: "sun.max.fill"
        )
        AppShortcut(
            intent: DecreaseXDRBoostIntent(),
            phrases: ["Decrease XDR Boost in \(.applicationName)"],
            shortTitle: "Decrease XDR Boost",
            systemImageName: "sun.min.fill"
        )
    }
}
