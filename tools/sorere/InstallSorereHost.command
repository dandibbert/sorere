#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/solunad"
DEST_DIR="$HOME/Library/Application Support/Sorere"
DEST="$DEST_DIR/solunad"
PLIST="$HOME/Library/LaunchAgents/com.dandibbert.sorere.host.plist"
LOG="$HOME/Library/Logs/SorereHost.log"

if [[ ! -x "$SRC" ]]; then
  echo "InstallSorereHost: solunad is missing next to this script."
  exit 1
fi

DEVICES="$("$SRC" --list-devices 2>&1 || true)"
if ! printf '%s\n' "$DEVICES" | grep -Fq "BlackHole 2ch"; then
  echo "BlackHole 2ch was not found. Install it before enabling auto-start."
  exit 2
fi

mkdir -p "$DEST_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp "$SRC" "$DEST"
chmod +x "$DEST"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.dandibbert.sorere.host</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST</string>
    <string>--rx</string>
    <string>--device</string>
    <string>BlackHole 2ch</string>
    <string>--port</string>
    <string>5004</string>
    <string>--rate</string>
    <string>48000</string>
    <string>--channels</string>
    <string>2</string>
    <string>--codec</string>
    <string>pcm</string>
    <string>--mode</string>
    <string>jam</string>
    <string>--no-relay</string>
    <string>--no-auto-tune</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SORERE_HOST_MODE</key>
    <string>1</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$UID" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl kickstart -k "gui/$UID/com.dandibbert.sorere.host"

echo "Sorere Host installed and started."
echo "Output device: BlackHole 2ch"
echo "Log: $LOG"
