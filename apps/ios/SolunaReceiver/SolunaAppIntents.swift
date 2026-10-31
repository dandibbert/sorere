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
    static let solunaIntentRecordStart   = Notification.Name("solunaIntentRecordStart")
    static let solunaIntentRecordStop    = Notification.Name("solunaIntentRecordStop")
    static let solunaIntentRecordToggle  = Notification.Name("solunaIntentRecordToggle")
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

// MARK: - Recording Intents

@available(iOS 16.0, *)
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Soluna Recording"
    static var description = IntentDescription("Start recording the audio Soluna is receiving. Starts playback first if it is stopped.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentRecordStart, object: nil)
        return .result(dialog: "Recording started.")
    }
}

@available(iOS 16.0, *)
struct StopRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Soluna Recording"
    static var description = IntentDescription("Stop the current Soluna recording and save it to the Documents folder.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentRecordStop, object: nil)
        return .result(dialog: "Recording stopped.")
    }
}

@available(iOS 16.0, *)
struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Soluna Recording"
    static var description = IntentDescription("Start recording if idle, stop recording if active.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(name: .solunaIntentRecordToggle, object: nil)
        return .result(dialog: "Recording toggled.")
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
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record with \(.applicationName)",
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop recording in \(.applicationName)",
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ToggleRecordingIntent(),
            phrases: [
                "Toggle recording in \(.applicationName)",
            ],
            shortTitle: "Toggle Recording",
            systemImageName: "record.circle.fill"
        )
    }
}
