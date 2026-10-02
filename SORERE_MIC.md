# Sorere Mic MVP

Sorere Mic is a focused personal-use derivative of OpenSonic/Soluna for one job:

> use an iPhone as a low-latency wireless microphone for a Mac on the same LAN.

The MVP deliberately avoids the public radio/relay product flow.

## Audio path

```text
iPhone microphone
  -> 48 kHz PCM / OSTP
  -> Bonjour discovers the Mac
  -> direct LAN UDP to Mac:5004
  -> Sorere Host (solunad on macOS)
  -> BlackHole 2ch
  -> any macOS app that accepts BlackHole 2ch as microphone input
```

No Soluna account, WAN relay, or iOS multicast entitlement is required for this path. Bonjour is used only to discover the Mac; microphone audio itself is unicast UDP.

## Requirements

- iPhone / iPad on iOS 16 or newer
- Mac on the same local network
- BlackHole 2ch installed on the Mac
- your own signing method for the unsigned iOS IPA

## GitHub Actions artifacts

The **Sorere Mic** workflow produces:

- `SorereMic-unsigned-ipa` — unsigned iPhone app
- `SorereHost-macos-arm64` — Apple Silicon Mac host bundle

The IPA is intentionally unsigned. Re-sign it with your own certificate/provisioning profile before installing it on a physical iPhone.

## Quick test

1. Download and unzip `SorereHost-macos-arm64` on the Mac.
2. Double-click `SorereHost.command`.
3. Install a re-signed `SorereMic-unsigned.ipa` on the iPhone.
4. Put the iPhone and Mac on the same LAN.
5. Open **Sorere Mic** and tap the large microphone button.
6. On the Mac, open QuickTime Player -> **File -> New Audio Recording**.
7. Select **BlackHole 2ch** as the microphone input.
8. Speak into the iPhone. QuickTime's input meter should move.

Do not select BlackHole as the Mac's global speaker output just for this test. Sorere Host targets it directly.

## Start Sorere Host automatically

After the manual test works, double-click:

```text
InstallSorereHost.command
```

It installs the host binary under:

```text
~/Library/Application Support/Sorere/solunad
```

and creates a per-user LaunchAgent:

```text
~/Library/LaunchAgents/com.dandibbert.sorere.host.plist
```

The host starts at login and is kept alive. Logs are written to:

```text
~/Library/Logs/SorereHost.log
```

To remove it, run `UninstallSorereHost.command`.

## MVP validation

Before adding menu-bar polish, validate these four things on real hardware:

1. **Audio path:** iPhone speech reaches BlackHole 2ch reliably.
2. **Latency:** speech input latency is acceptable for calls/dictation (the Mac host uses the ~20 ms default receive buffer rather than the 100 ms Wi-Fi profile).
3. **Background:** lock the iPhone for at least 10 minutes while transmitting.
4. **Recovery:** toggle Wi-Fi off and back on and verify transmission resumes or can be restarted cleanly.

## Current limitations

- LAN-only by design.
- The first MVP automatically selects the first Sorere/OpenSonic host found by Bonjour; a manual Mac IP fallback is available.
- The iPhone app must have microphone permission.
- iOS may interrupt the audio session for phone calls, Siri, route changes, or another app taking exclusive audio.
- The Mac host expects a CoreAudio output device named exactly `BlackHole 2ch`.
- Automatic post-network-loss restart is not yet considered verified until real-device testing.

## License

This repository retains the upstream **OpenSonic Community License v1.0**. This derivative must retain that license. See `LICENSE`.
