//
//  ContentView.swift
//  Sorere Mic
//
//  Purpose-built iPhone -> Mac microphone UI.
//  The Mac is discovered with Bonjour; microphone audio is sent by unicast UDP.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var receiver = AudioReceiver()
    @StateObject private var deviceBrowser = DeviceBrowser()

    @AppStorage("sorere.autoStartMic") private var autoStartMic = false
    @AppStorage("sorere.lastMacHost") private var lastMacHost = ""

    @State private var macHost: String?
    @State private var manualHost = ""
    @State private var didAutoStart = false
    @State private var permissionDenied = false
    @State private var showDetails = false

    private let audioPort: UInt16 = 5004

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                Spacer(minLength: 20)

                VStack(spacing: 8) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 44, weight: .medium))
                        .symbolRenderingMode(.hierarchical)

                    Text("Sorere Mic")
                        .font(.largeTitle.bold())

                    Text("Use this iPhone as a wireless microphone for your Mac.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                statusCard

                Button(action: toggleMic) {
                    ZStack {
                        Circle()
                            .fill(receiver.isMicTransmitting ? Color.red.opacity(0.16) : Color.accentColor.opacity(0.12))
                            .frame(width: 184, height: 184)

                        Circle()
                            .fill(receiver.isMicTransmitting ? Color.red : (macHost == nil ? Color.secondary : Color.accentColor))
                            .frame(width: 136, height: 136)
                            .shadow(radius: receiver.isMicTransmitting ? 18 : 8)

                        Image(systemName: receiver.isMicTransmitting ? "mic.fill" : "mic")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(macHost == nil && !receiver.isMicTransmitting)
                .accessibilityLabel(receiver.isMicTransmitting ? "Stop microphone" : "Start microphone")

                VStack(spacing: 10) {
                    Text(receiver.isMicTransmitting ? "MICROPHONE ON" :
                            (macHost == nil ? "Waiting for Mac" : "Tap to start"))
                        .font(.headline)
                        .foregroundStyle(receiver.isMicTransmitting ? .red : .secondary)

                    levelMeter
                        .frame(height: 18)
                        .opacity(receiver.isMicTransmitting ? 1 : 0.35)
                }

                if permissionDenied {
                    Label("Microphone permission is disabled. Enable it in Settings → Privacy & Security → Microphone.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                Toggle("Start microphone when Mac is found", isOn: $autoStartMic)
                    .font(.subheadline)

                DisclosureGroup("Connection details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        detailRow("Input", inputRouteName)
                        detailRow("Transport", "LAN unicast · PCM · 48 kHz")
                        detailRow("Mac", macHost ?? "Searching…")
                        detailRow("Destination", macHost.map { "\($0):\(audioPort)" } ?? "—")
                        detailRow("Packets sent", "\(receiver.txPacketsSent)")

                        Divider()

                        Text("Manual Mac IP")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("192.168.1.10", text: $manualHost)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Use") {
                                useManualHost()
                            }
                            .disabled(manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Text("Sorere Host advertises itself over Bonjour. Audio itself is direct UDP to the Mac, so no multicast entitlement or public relay is needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .onAppear {
            refreshPermissionState()

            if !lastMacHost.isEmpty {
                setMacHost(lastMacHost)
            }

            // Auto-start only after a fresh Bonjour result. A persisted IP may
            // be stale after DHCP changes, so never auto-key the mic from cache.
            deviceBrowser.startScanning()
        }
        .onDisappear {
            deviceBrowser.stopScanning()
        }
        .onChange(of: deviceBrowser.devices) { devices in
            guard let device = devices.first else { return }
            setMacHost(device.host)
            maybeAutoStart()
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            if macHost == nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(receiver.isMicTransmitting ? Color.green : Color.blue)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if macHost == nil {
                Button("Scan") {
                    deviceBrowser.startScanning()
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusTitle: String {
        if receiver.isMicTransmitting { return "Streaming to Mac" }
        if macHost != nil { return "Mac ready" }
        return "Finding Sorere Host…"
    }

    private var statusSubtitle: String {
        if receiver.isMicTransmitting {
            return "Direct LAN audio · background/lock-screen capable"
        }
        if let macHost {
            return "Found \(macHost)"
        }
        return "Start Sorere Host on the Mac and keep both devices on the same LAN."
    }

    private var levelMeter: some View {
        GeometryReader { proxy in
            let level = max(0, min(CGFloat(receiver.micInputLevel), 1))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(receiver.isMicTransmitting ? Color.green : Color.secondary)
                    .frame(width: max(4, proxy.size.width * level))
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var inputRouteName: String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "iPhone microphone"
    }

    private func setMacHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        macHost = trimmed
        lastMacHost = trimmed
        receiver.multicastGroup = trimmed   // OpenSonic TX accepts unicast IPv4 here too.
        receiver.port = audioPort
        receiver.channels = 2
        receiver.micGlobal = false
    }

    private func useManualHost() {
        setMacHost(manualHost)
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
            guard let macHost else { return }
            setMacHost(macHost)
        }

        receiver.toggleMic()

        // Permission callbacks are asynchronous; refresh after the system sheet settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshPermissionState()
        }
    }
}
