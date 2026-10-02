//
//  ContentView.swift
//  Sorere Mic
//
//  Focused iPhone microphone UI. Responsive on Dynamic Island devices.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var receiver = AudioReceiver()
    @StateObject private var deviceBrowser = DeviceBrowser()

    @AppStorage("sorere.autoStartMic") private var autoStartMic = false
    @AppStorage("sorere.lastMacHost") private var lastMacHost = ""

    @State private var macHost: String?
    @State private var macName: String?
    @State private var manualHost = ""
    @State private var didAutoStart = false
    @State private var permissionDenied = false
    @State private var showSettings = false

    private let audioPort: UInt16 = 5004

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        header
                        connectionCard
                        microphoneCard(availableWidth: proxy.size.width - 40)

                        if permissionDenied {
                            warningCard(
                                title: "Microphone access is off",
                                message: "Enable Sorere Mic in Settings → Privacy & Security → Microphone."
                            )
                        } else if let error = receiver.errorMessage, !error.isEmpty {
                            warningCard(title: "Audio error", message: error)
                        }

                        footer
                    }
                    .frame(maxWidth: 540)
                    .frame(minHeight: max(0, proxy.size.height - 20), alignment: .top)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
        .onAppear {
            refreshPermissionState()

            if !lastMacHost.isEmpty {
                setMacHost(lastMacHost, name: nil)
            }

            deviceBrowser.startScanning()
        }
        .onDisappear {
            deviceBrowser.stopScanning()
        }
        .onChange(of: deviceBrowser.devices) { devices in
            guard let device = devices.first else { return }
            setMacHost(device.host, name: device.name)
            maybeAutoStart()
        }
    }

    private var background: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(receiver.isMicTransmitting ? 0.14 : 0.08),
                    Color.clear,
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sorere Mic")
                    .font(.system(.title, design: .rounded, weight: .bold))

                Text("iPhone → Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var connectionCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(connectionTint.opacity(0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: macHost == nil ? "macmini" : "macmini.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(connectionTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(connectionTitle)
                        .font(.headline)
                        .lineLimit(1)

                    Circle()
                        .fill(connectionTint)
                        .frame(width: 7, height: 7)
                }

                Text(connectionSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if macHost == nil {
                Button("Scan") {
                    deviceBrowser.startScanning()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func microphoneCard(availableWidth: CGFloat) -> some View {
        let buttonSize = max(126, min(158, availableWidth * 0.40))

        return VStack(spacing: 20) {
            VStack(spacing: 5) {
                Text(receiver.isMicTransmitting ? "Live" : (macHost == nil ? "Waiting" : "Ready"))
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text(micSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }

            Button(action: toggleMic) {
                ZStack {
                    Circle()
                        .fill(micTint.opacity(0.12))
                        .frame(width: buttonSize + 28, height: buttonSize + 28)

                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    micTint.opacity(0.90),
                                    micTint
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: buttonSize, height: buttonSize)
                        .shadow(color: micTint.opacity(receiver.isMicTransmitting ? 0.30 : 0.16),
                                radius: receiver.isMicTransmitting ? 22 : 12,
                                y: 8)

                    Image(systemName: receiver.isMicTransmitting ? "mic.fill" : "mic")
                        .font(.system(size: buttonSize * 0.34, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(macHost == nil && !receiver.isMicTransmitting)
            .opacity((macHost == nil && !receiver.isMicTransmitting) ? 0.52 : 1)
            .accessibilityLabel(receiver.isMicTransmitting ? "Stop microphone" : "Start microphone")

            LevelBars(level: receiver.micInputLevel,
                      active: receiver.isMicTransmitting,
                      tint: micTint)
                .frame(height: 34)

            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                Text(inputRouteName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if receiver.isMicTransmitting {
                    Text("\(receiver.txPacketsSent) packets")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: receiver.isMicTransmitting ? "lock.open.fill" : "wifi")
            Text(receiver.isMicTransmitting
                 ? "You can lock the iPhone while Sorere Mic is running."
                 : "Keep the Mac host running on the same local network.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func warningCard(title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    LabeledContent("Mac", value: macName ?? (macHost == nil ? "Not found" : "Sorere Host"))
                    LabeledContent("Address", value: macHost ?? "—")

                    Button {
                        deviceBrowser.startScanning()
                    } label: {
                        Label("Scan for Mac", systemImage: "arrow.clockwise")
                    }

                    HStack {
                        TextField("Mac IP address", text: $manualHost)
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("Use") {
                            useManualHost()
                        }
                        .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Behavior") {
                    Toggle("Start microphone when Mac is found", isOn: $autoStartMic)
                }

                Section("Audio") {
                    LabeledContent("Input", value: inputRouteName)
                    LabeledContent("Format", value: "48 kHz · stereo transport")
                    LabeledContent("Transport", value: "Direct LAN UDP")
                }

                Section {
                    Text("Sorere Mic sends microphone audio only to the selected Mac on your local network. No public relay is used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var connectionTint: Color {
        if receiver.isMicTransmitting { return .green }
        if macHost != nil { return .blue }
        return .secondary
    }

    private var micTint: Color {
        receiver.isMicTransmitting ? .red : .accentColor
    }

    private var connectionTitle: String {
        if receiver.isMicTransmitting { return macName ?? "Mac connected" }
        if macHost != nil { return macName ?? "Mac ready" }
        return "Looking for your Mac"
    }

    private var connectionSubtitle: String {
        if receiver.isMicTransmitting {
            return macHost.map { "Streaming directly to \($0)" } ?? "Streaming on your local network"
        }
        if let host = macHost {
            return "Ready at \(host)"
        }
        return "Open Sorere on the Mac. Discovery is automatic."
    }

    private var micSubtitle: String {
        if receiver.isMicTransmitting {
            return "Your iPhone microphone is being sent to BlackHole on the Mac."
        }
        if macHost != nil {
            return "Tap the microphone when you want to use the iPhone."
        }
        return "Sorere will enable the microphone as soon as a Mac host is available."
    }

    private var inputRouteName: String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "iPhone Microphone"
    }

    private func setMacHost(_ host: String, name: String?) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        macHost = trimmed
        if let name, !name.isEmpty {
            macName = name
        }
        lastMacHost = trimmed

        receiver.multicastGroup = trimmed
        receiver.port = audioPort
        receiver.channels = 2
        receiver.micGlobal = false
    }

    private func useManualHost() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        setMacHost(host, name: "Manual Mac")
        manualHost = ""
        maybeAutoStart()
    }

    private func refreshPermissionState() {
        permissionDenied = AVAudioSession.sharedInstance().recordPermission == .denied
    }

    private func maybeAutoStart() {
        guard autoStartMic, !didAutoStart, macHost != nil, !receiver.isMicTransmitting else { return }
        didAutoStart = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            toggleMic()
        }
    }

    private func toggleMic() {
        refreshPermissionState()
        guard !permissionDenied else { return }

        if !receiver.isMicTransmitting {
            guard let host = macHost else { return }
            setMacHost(host, name: macName)
        }

        receiver.toggleMic()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshPermissionState()
        }
    }
}

private struct LevelBars: View {
    let level: Float
    let active: Bool
    let tint: Color

    private let count = 22

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 3
            let width = max(2, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            let normalized = max(0, min(CGFloat(level), 1))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<count, id: \.self) { index in
                    let threshold = CGFloat(index + 1) / CGFloat(count)
                    let shaped = max(0.12, 1 - abs(CGFloat(index) - CGFloat(count - 1) / 2) / CGFloat(count))
                    Capsule()
                        .fill(active && normalized >= threshold ? tint : Color.secondary.opacity(0.18))
                        .frame(width: width, height: 9 + 24 * shaped)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
