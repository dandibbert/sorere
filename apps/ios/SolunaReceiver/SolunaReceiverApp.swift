//
//  SorereMicApp.swift
//  Sorere Mic
//
//  Minimal app entry point for the LAN microphone client.
//

import SwiftUI
import AVFoundation

@main
struct SolunaReceiverApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { phase in
            // The capture AudioUnit owns the background-audio assertion while the
            // microphone is running. Re-activate the session after iOS route or
            // lifecycle transitions without introducing any relay/account work.
            if phase == .active || phase == .background {
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
    }
}
