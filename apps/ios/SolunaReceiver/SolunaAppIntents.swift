//
//  SolunaAppIntents.swift
//  Sorere Mic
//
//  Shortcuts / Siri actions to start, stop and toggle the iPhone → Mac microphone.
//
//  Intents write the requested command to UserDefaults and post a notification.
//  ContentView consumes the command on the notification AND on appear, so a cold
//  launch triggered by the intent (app not yet running) is not lost.
//

import AppIntents
import Foundation

// MARK: - Command plumbing

enum SorereMicIntentCommand {
    static let defaultsKey = "sorere.pendingMicIntent"
    static let start  = "start"
    static let stop   = "stop"
    static let toggle = "toggle"

    static func send(_ command: String) {
        UserDefaults.standard.set(command, forKey: defaultsKey)
        NotificationCenter.default.post(name: .sorereMicIntent, object: nil)
    }

    /// Returns and clears the pending command, if any.
    static func consume() -> String? {
        let defaults = UserDefaults.standard
        guard let command = defaults.string(forKey: defaultsKey) else { return nil }
        defaults.removeObject(forKey: defaultsKey)
        return command
    }
}

extension Notification.Name {
    static let sorereMicIntent = Notification.Name("sorereMicIntent")
    /// Still posted by SleepTimer; kept so it keeps compiling (nothing observes it in Sorere Mic).
    static let solunaIntentStop = Notification.Name("solunaIntentStop")
}

// MARK: - Intents

@available(iOS 16.0, *)
struct StartMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Sorere Mic"
    static var description = IntentDescription("Start sending the iPhone microphone to your Mac.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SorereMicIntentCommand.send(SorereMicIntentCommand.start)
        return .result(dialog: "Sorere Mic on.")
    }
}

@available(iOS 16.0, *)
struct StopMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Sorere Mic"
    static var description = IntentDescription("Stop sending the iPhone microphone to your Mac.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SorereMicIntentCommand.send(SorereMicIntentCommand.stop)
        return .result(dialog: "Sorere Mic off.")
    }
}

@available(iOS 16.0, *)
struct ToggleMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Sorere Mic"
    static var description = IntentDescription("Turn the iPhone → Mac microphone on if it is off, off if it is on.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SorereMicIntentCommand.send(SorereMicIntentCommand.toggle)
        return .result(dialog: "Sorere Mic toggled.")
    }
}

// MARK: - App Shortcuts

@available(iOS 16.0, *)
struct SolunaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartMicIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Turn on \(.applicationName)",
            ],
            shortTitle: "Start Mic",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopMicIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "Turn off \(.applicationName)",
            ],
            shortTitle: "Stop Mic",
            systemImageName: "mic.slash.fill"
        )
        AppShortcut(
            intent: ToggleMicIntent(),
            phrases: [
                "Toggle \(.applicationName)",
            ],
            shortTitle: "Toggle Mic",
            systemImageName: "mic.circle"
        )
    }
}
