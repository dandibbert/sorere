//
//  SolunaAppIntents.swift
//  SolunaReceiver
//
//  Siri Shortcuts via AppIntents framework (iOS 16+).
//  Intents post notifications that ContentView observes to trigger playback.
//

import AppIntents
import Foundation

// MARK: - Channel Enum

@available(iOS 16.0, *)
enum SolunaChannelEnum: String, AppEnum {
    case soluna, jazz, lofi, chill, dance, bjj, yuki

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Soluna Channel"

    static var caseDisplayRepresentations: [SolunaChannelEnum: DisplayRepresentation] = [
        .soluna: "Soluna",
        .jazz:   "Jazz",
        .lofi:   "Lo-Fi",
        .chill:  "Chill",
        .dance:  "Dance",
        .bjj:    "BJJ",
        .yuki:   "Yuki",
    ]
}

// MARK: - Notification Names

extension Notification.Name {
    static let solunaIntentPlay          = Notification.Name("solunaIntentPlay")
    static let solunaIntentStop          = Notification.Name("solunaIntentStop")
    static let solunaIntentSwitchChannel = Notification.Name("solunaIntentSwitchChannel")
    static let solunaIntentMicStart      = Notification.Name("solunaIntentMicStart")
    static let solunaIntentMicStop       = Notification.Name("solunaIntentMicStop")
    static let solunaIntentMicToggle     = Notification.Name("solunaIntentMicToggle")
}

// MARK: - Play Intent

@available(iOS 16.0, *)
struct PlaySolunaIntent: AppIntent {
    static var title: LocalizedStringResource = "Play Soluna Radio"
    static var description = IntentDescription("Start playing Soluna Radio, optionally on a specific channel.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Channel")
    var channel: SolunaChannelEnum?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ch = channel?.rawValue ?? UserDefaults.standard.string(forKey: "channel") ?? "soluna"
        UserDefaults.standard.set(ch, forKey: "siri_command")
        NotificationCenter.default.post(name: .solunaIntentPlay, object: nil, userInfo: ["channel": ch])
        let label = channel?.rawValue.capitalized ?? "Soluna"
        return .result(dialog: "Playing \(label) on Soluna Radio.")
    }
}

// MARK: - Stop Intent

@available(iOS 16.0, *)
struct StopSolunaIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Soluna Radio"
    static var description = IntentDescription("Stop playing Soluna Radio.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentStop, object: nil)
        return .result(dialog: "Soluna Radio stopped.")
    }
}

// MARK: - Switch Channel Intent

@available(iOS 16.0, *)
struct SwitchChannelIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch Soluna Channel"
    static var description = IntentDescription("Switch Soluna Radio to a different channel.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Channel")
    var channel: SolunaChannelEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ch = channel.rawValue
        UserDefaults.standard.set(ch, forKey: "siri_command")
        NotificationCenter.default.post(name: .solunaIntentSwitchChannel, object: nil, userInfo: ["channel": ch])
        return .result(dialog: "Switched to \(channel.rawValue.capitalized).")
    }
}

// MARK: - Mic (iPhone → Mac audio input) Intents
//
// Drive the same mic-transmit path as the Mic tab: the iPhone microphone is
// sent over LAN multicast / WAN relay so the Mac side can use it as audio input.

@available(iOS 16.0, *)
struct StartMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Soluna Mic"
    static var description = IntentDescription("Start sending the iPhone microphone to Soluna (Mac audio input).")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Channel", description: "Defaults to the channel set in the Mic tab.")
    var channel: SolunaChannelEnum?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var info: [String: Any] = [:]
        if let channel { info["channel"] = channel.rawValue }
        NotificationCenter.default.post(name: .solunaIntentMicStart, object: nil, userInfo: info)
        return .result(dialog: "Soluna mic on.")
    }
}

@available(iOS 16.0, *)
struct StopMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Soluna Mic"
    static var description = IntentDescription("Stop sending the iPhone microphone to Soluna.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentMicStop, object: nil)
        return .result(dialog: "Soluna mic off.")
    }
}

@available(iOS 16.0, *)
struct ToggleMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Soluna Mic"
    static var description = IntentDescription("Turn the iPhone microphone feed to Soluna on if off, off if on.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentMicToggle, object: nil)
        return .result(dialog: "Soluna mic toggled.")
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct SolunaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlaySolunaIntent(),
            phrases: [
                "Play \(.applicationName)",
                "Play \(.applicationName) radio",
                "Start \(.applicationName)",
            ],
            shortTitle: "Play Soluna",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopSolunaIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Stop \(.applicationName) radio",
                "Pause \(.applicationName)",
            ],
            shortTitle: "Stop Soluna",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: SwitchChannelIntent(),
            phrases: [
                "Switch \(.applicationName) to \(\.$channel)",
                "Play \(\.$channel) on \(.applicationName)",
            ],
            shortTitle: "Switch Channel",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: StartMicIntent(),
            phrases: [
                "Start mic in \(.applicationName)",
                "Turn on \(.applicationName) mic",
            ],
            shortTitle: "Start Mic",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopMicIntent(),
            phrases: [
                "Stop mic in \(.applicationName)",
                "Turn off \(.applicationName) mic",
            ],
            shortTitle: "Stop Mic",
            systemImageName: "mic.slash.fill"
        )
        AppShortcut(
            intent: ToggleMicIntent(),
            phrases: [
                "Toggle \(.applicationName) mic",
            ],
            shortTitle: "Toggle Mic",
            systemImageName: "mic.circle"
        )
    }
}
