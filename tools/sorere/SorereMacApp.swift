//
//  SorereMacApp.swift
//  Sorere
//
//  Native macOS companion for the standalone Sorere host.
//

import SwiftUI
import Foundation
import AppKit
import ServiceManagement

enum HostStatus: Equatable {
    case starting
    case waiting
    case connected
    case streaming
    case stopped
    case testing
    case error(String)

    var title: String {
        switch self {
        case .starting: return "Starting"
        case .waiting: return "Waiting for iPhone"
        case .connected: return "iPhone connected"
        case .streaming: return "Microphone live"
        case .stopped: return "Host paused"
        case .testing: return "Testing BlackHole"
        case .error: return "Needs attention"
        }
    }

    var subtitle: String {
        switch self {
        case .starting:
            return "Opening BlackHole and local network services…"
        case .waiting:
            return "Open Sorere Mic on the iPhone. Discovery is automatic."
        case .connected:
            return "The iPhone is connected. Waiting for microphone audio."
        case .streaming:
            return "iPhone audio is flowing into BlackHole 2ch."
        case .stopped:
            return "Sorere is not currently accepting microphone audio."
        case .testing:
            return "Sending a local test tone through BlackHole."
        case .error(let message):
            return message
        }
    }

    var symbol: String {
        switch self {
        case .starting: return "arrow.triangle.2.circlepath"
        case .waiting: return "iphone.radiowaves.left.and.right"
        case .connected: return "link"
        case .streaming: return "mic.fill"
        case .stopped: return "pause.fill"
        case .testing: return "waveform.path.ecg"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .streaming: return .green
        case .connected: return .blue
        case .waiting, .starting: return .secondary
        case .stopped: return .orange
        case .testing: return .purple
        case .error: return .red
        }
    }
}

final class SorereAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?

    private var controller: HostController {
        HostController.shared
    }

    private var showInDock: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "sorere.showInDock") == nil {
            return true
        }
        return defaults.bool(forKey: "sorere.showInDock")
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()

        // WindowGroup creates the first window automatically. In menu-bar-only
        // mode keep it alive but hidden so "Open Sorere" can always restore it.
        if !showInDock {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.mainWindow?.orderOut(nil)
                NSApp.windows
                    .filter { $0.isVisible && !($0 is NSPanel) }
                    .forEach { $0.orderOut(nil) }
            }
        }
    }

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Sorere")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Sorere"
        }

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: controller.status.title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let address = controller.iPhoneAddress {
            let device = NSMenuItem(title: "iPhone · \(address)", action: nil, keyEquivalent: "")
            device.isEnabled = false
            menu.addItem(device)
        }

        menu.addItem(.separator())

        let open = NSMenuItem(
            title: "Open Sorere",
            action: #selector(openSorere),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        let host = NSMenuItem(
            title: controller.isRunning ? "Pause Host" : "Start Host",
            action: #selector(toggleHost),
            keyEquivalent: ""
        )
        host.target = self
        menu.addItem(host)

        let test = NSMenuItem(
            title: "Test BlackHole",
            action: #selector(testBlackHole),
            keyEquivalent: ""
        )
        test.target = self
        test.isEnabled = !controller.isTesting
        menu.addItem(test)

        menu.addItem(.separator())

        let dock = NSMenuItem(
            title: "Show in Dock",
            action: #selector(toggleDock),
            keyEquivalent: ""
        )
        dock.target = self
        dock.state = controller.showInDock ? .on : .off
        menu.addItem(dock)

        let launch = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launch.target = self
        launch.state = controller.launchAtLogin ? .on : .off
        menu.addItem(launch)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Sorere",
            action: #selector(quitSorere),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openSorere() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // The window should normally be retained because windowShouldClose only
        // hides it. Keep a defensive fallback for unusual scene recreation.
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            registerMainWindow(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func toggleHost() {
        controller.isRunning ? controller.stop() : controller.startIfNeeded()
    }

    @objc private func testBlackHole() {
        controller.runBlackHoleTest()
    }

    @objc private func toggleDock() {
        controller.setShowInDock(!controller.showInDock)
        if controller.showInDock {
            openSorere()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        controller.setLaunchAtLogin(!controller.launchAtLogin)
    }

    @objc private func quitSorere() {
        NSApp.terminate(nil)
    }
}

final class HostController: ObservableObject {
    static let shared = HostController()
    @Published private(set) var status: HostStatus = .starting
    @Published private(set) var level: Double = 0
    @Published private(set) var iPhoneAddress: String?
    @Published private(set) var isRunning = false
    @Published private(set) var isTesting = false
    @Published var launchAtLogin = false
    @Published var showInDock = true
    @Published var testResult: String?

    private enum Mode {
        case host
        case test
    }

    private var process: Process?
    private var outputPipe: Pipe?
    private var lineBuffer = ""
    private var mode: Mode = .host
    private var intentionalStop = false
    private var restartAfterTest = false
    private var terminationObserver: NSObjectProtocol?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let defaults = UserDefaults.standard
        showInDock = defaults.object(forKey: "sorere.showInDock") == nil
            ? true
            : defaults.bool(forKey: "sorere.showInDock")

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.process?.terminate()
        }

        // Do not depend on the main window appearing. Menu-bar-only launches
        // should bring up the audio host immediately in the background.
        DispatchQueue.main.async { [weak self] in
            self?.startIfNeeded()
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        process?.terminate()
    }

    var menuSymbol: String { status.symbol }

    func startIfNeeded() {
        guard process == nil, !isTesting else { return }
        startProcess(arguments: [], mode: .host)
    }

    func restart() {
        let hadProcess = process != nil
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + (hadProcess ? 0.45 : 0.05)) { [weak self] in
            self?.startIfNeeded()
        }
    }

    func stop() {
        intentionalStop = true
        process?.terminate()
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        lineBuffer = ""
        isRunning = false
        isTesting = false
        level = 0
        status = .stopped
    }

    func runBlackHoleTest() {
        guard !isTesting else { return }
        restartAfterTest = process != nil
        stop()
        testResult = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.startProcess(arguments: ["--test-tone"], mode: .test)
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            testResult = "Could not change launch-at-login: \(error.localizedDescription)"
        }
    }

    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        UserDefaults.standard.set(enabled, forKey: "sorere.showInDock")

        if enabled {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)

            // Keep the host and native status item alive. Hide ordinary windows
            // without destroying them so the status item can always reopen UI.
            DispatchQueue.main.async {
                NSApp.windows
                    .filter { $0.isVisible && !($0 is NSPanel) }
                    .forEach { $0.orderOut(nil) }
            }
        }
    }

    private func hostExecutableURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "sorere-host", withExtension: nil) {
            return bundled
        }

        let fallback = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("sorere-host")

        return FileManager.default.isExecutableFile(atPath: fallback.path) ? fallback : nil
    }

    private func startProcess(arguments: [String], mode: Mode) {
        guard process == nil else { return }
        guard let executable = hostExecutableURL() else {
            status = .error("The embedded Sorere host is missing.")
            return
        }

        self.mode = mode
        intentionalStop = false
        lineBuffer = ""
        level = 0
        iPhoneAddress = nil

        if mode == .host {
            status = .starting
            isTesting = false
        } else {
            status = .testing
            isTesting = true
        }

        let task = Process()
        task.executableURL = executable
        task.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        env["SORERE_UI"] = "1"
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consume(chunk)
            }
        }

        task.terminationHandler = { [weak self, weak task] finished in
            DispatchQueue.main.async {
                guard let self, let task, self.process === task else { return }

                self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                self.outputPipe = nil
                self.process = nil
                self.isRunning = false
                self.level = 0

                let wasTest = self.mode == .test
                self.isTesting = false

                if wasTest {
                    if self.testResult == nil {
                        self.testResult = finished.terminationStatus == 0
                            ? "BlackHole test finished."
                            : "BlackHole test failed."
                    }

                    if self.restartAfterTest {
                        self.restartAfterTest = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                            self.startIfNeeded()
                        }
                    } else if self.status == .testing {
                        self.status = .stopped
                    }
                    return
                }

                if !self.intentionalStop && finished.terminationStatus != 0 {
                    self.status = .error("Sorere Host stopped unexpectedly.")
                } else if self.intentionalStop {
                    self.status = .stopped
                }
            }
        }

        do {
            try task.run()
            process = task
            outputPipe = pipe
            isRunning = mode == .host
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            status = .error("Could not start Sorere Host: \(error.localizedDescription)")
            process = nil
            outputPipe = nil
            isRunning = false
            isTesting = false
        }
    }

    private func consume(_ chunk: String) {
        lineBuffer += chunk

        while let newline = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer.removeSubrange(...newline)
            handle(line)
        }
    }

    private func handle(_ line: String) {
        guard !line.isEmpty else { return }

        if line == "BlackHole ready" {
            if mode == .host {
                status = .waiting
            }
            return
        }

        if line.hasPrefix("iPhone connected") {
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            iPhoneAddress = parts.count >= 3 ? parts[2] : nil
            status = .connected
            return
        }

        if line == "Audio flowing to BlackHole" {
            status = .streaming
            return
        }

        if line.hasPrefix("LEVEL ") {
            if let value = Double(line.dropFirst(6)) {
                level = max(0, min(value, 1))
                if value > 0.001, mode == .host {
                    status = .streaming
                }
            }
            return
        }

        if line == "BlackHole loopback confirmed" {
            testResult = "BlackHole is working."
            status = .testing
            process?.terminate()
            return
        }

        if line.hasPrefix("ERROR:") {
            let message = line.replacingOccurrences(of: "ERROR:", with: "")
                .trimmingCharacters(in: .whitespaces)
            if mode == .test {
                testResult = message
                process?.terminate()
            } else {
                status = .error(message)
            }
        }
    }
}

@main
struct SorereMacApp: App {
    @NSApplicationDelegateAdaptor(SorereAppDelegate.self) private var appDelegate
    @StateObject private var controller = HostController.shared

    var body: some Scene {
        WindowGroup("Sorere", id: "main") {
            MainWindow()
                .environmentObject(controller)
                .background(MainWindowRegistrar())
                .onAppear {
                    controller.startIfNeeded()
                }
        }
        .defaultSize(width: 510, height: 470)
    }
}

private struct MainWindowRegistrar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window,
                  let delegate = NSApp.delegate as? SorereAppDelegate else { return }
            delegate.registerMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window,
                  let delegate = NSApp.delegate as? SorereAppDelegate else { return }
            delegate.registerMainWindow(window)
        }
    }
}

private struct MainWindow: View {
    @EnvironmentObject private var controller: HostController

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    controller.status.tint.opacity(0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                header
                statusCard
                routeCard
                controls
                footer
            }
            .padding(24)
        }
        .frame(minWidth: 470, minHeight: 430)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sorere")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("iPhone microphone for Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(status: controller.status)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(controller.status.tint.opacity(0.14))
                    .frame(width: 74, height: 74)

                Image(systemName: controller.status.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(controller.status.tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(controller.status.title)
                    .font(.title3.weight(.semibold))

                Text(controller.status.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let address = controller.iPhoneAddress {
                    Label(address, systemImage: "iphone")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var routeCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Audio route")
                    .font(.headline)
                Spacer()
                if controller.status == .streaming {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                RouteChip(symbol: "iphone", title: "iPhone")
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                RouteChip(symbol: "circle.grid.cross.fill", title: "BlackHole 2ch")
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                RouteChip(symbol: "mic.fill", title: "Your apps")
            }

            MacLevelMeter(level: controller.level,
                          active: controller.status == .streaming,
                          tint: controller.status.tint)

            Text("Choose “BlackHole 2ch” as the microphone/input device in ChatGPT, Discord, QuickTime, or any other Mac app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                controller.isRunning ? controller.stop() : controller.startIfNeeded()
            } label: {
                Label(controller.isRunning ? "Pause Host" : "Start Host",
                      systemImage: controller.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                controller.runBlackHoleTest()
            } label: {
                Label("Test BlackHole", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)
            .disabled(controller.isTesting)

            Spacer()

            if let result = controller.testResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(result.contains("working") ? .green : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)

            Toggle(
                "Show in Dock",
                isOn: Binding(
                    get: { controller.showInDock },
                    set: { controller.setShowInDock($0) }
                )
            )
            .toggleStyle(.switch)

            Spacer()

            Button("Restart Host") {
                controller.restart()
            }
            .buttonStyle(.link)
        }
        .font(.caption)
    }
}

private struct StatusBadge: View {
    let status: HostStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.tint)
                .frame(width: 7, height: 7)
            Text(status.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.tint.opacity(0.10), in: Capsule())
    }
}

private struct RouteChip: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }
}

private struct MacLevelMeter: View {
    let level: Double
    let active: Bool
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let normalized = max(0, min(level, 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(active ? tint : Color.secondary.opacity(0.35))
                    .frame(width: max(3, proxy.size.width * normalized))
            }
        }
        .frame(height: 9)
        .animation(.linear(duration: 0.08), value: level)
    }
}
