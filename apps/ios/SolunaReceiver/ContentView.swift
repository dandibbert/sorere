//
//  ContentView.swift
//  Sorere Mic
//
//  Purpose-built iPhone -> Mac microphone UI.
//  Transport remains OpenSonic OSTP multicast on the local network.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var receiver = AudioReceiver()

    @AppStorage("sorere.autoStartMic") private var autoStartMic = false
    @State private var didAutoStart = false
    @State private var permissionDenied = false
    @State private var showDetails = false

    private let multicastGroup = "239.69.0.1"
    private let multicastPort: UInt16 = 5004

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

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
                            .fill(receiver.isMicTransmitting ? Color.red : Color.accentColor)
                            .frame(width: 136, height: 136)
                            .shadow(radius: receiver.isMicTransmitting ? 18 : 8)

                        Image(systemName: receiver.isMicTransmitting ? "mic.fill" : "mic")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(receiver.isMicTransmitting ? "Stop microphone" : "Start microphone")

                VStack(spacing: 10) {
                    Text(receiver.isMicTransmitting ? "MICROPHONE ON" : "Tap to start")
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

                Toggle("Start microphone when app opens", isOn: $autoStartMic)
                    .font(.subheadline)

                DisclosureGroup("Connection details", isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 8) {
                        detailRow("Input", inputRouteName)
                        detailRow("Transport", "LAN multicast · PCM · 48 kHz")
                        detailRow("Destination", "\(multicastGroup):\(multicastPort)")
                        detailRow("Packets sent", "\(receiver.txPacketsSent)")
                        Text("The Mac host listens on the same LAN and writes directly to BlackHole 2ch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
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
            configureTransport()
            refreshPermissionState()

            guard autoStartMic, !didAutoStart else { return }
            didAutoStart = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if !receiver.isMicTransmitting {
                    toggleMic()
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(receiver.isMicTransmitting ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(receiver.isMicTransmitting ? "Streaming to Mac" : "Ready")
                    .font(.headline)
                Text(receiver.isMicTransmitting
                     ? "Keep this app running; locking the iPhone is supported."
                     : "Start Sorere Host on the Mac, then tap the microphone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func configureTransport() {
        receiver.multicastGroup = multicastGroup
        receiver.port = multicastPort
        receiver.channels = 2
        receiver.micGlobal = false
    }

    private func refreshPermissionState() {
        permissionDenied = AVAudioSession.sharedInstance().recordPermission == .denied
    }

    private func toggleMic() {
        configureTransport()
        refreshPermissionState()
        guard !permissionDenied else { return }
        receiver.toggleMic()

        // Permission callbacks are asynchronous; refresh after the system sheet settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            refreshPermissionState()
        }
    }
}
