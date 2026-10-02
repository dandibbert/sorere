#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/solunad"
DEVICE="BlackHole 2ch"

if [[ ! -x "$BIN" ]]; then
  echo "Sorere Host: solunad is missing next to this script."
  exit 1
fi

if [[ "${1:-}" == "--list-devices" ]]; then
  exec "$BIN" --list-devices
fi

DEVICES="$("$BIN" --list-devices 2>&1 || true)"
if ! printf '%s\n' "$DEVICES" | grep -Fq "$DEVICE"; then
  echo "Sorere Host: '$DEVICE' was not found."
  echo
  echo "Available audio devices:"
  printf '%s\n' "$DEVICES"
  echo
  echo "Install BlackHole 2ch, then run SorereHost.command again."
  exit 2
fi

echo "Sorere Host"
echo "  Input : iPhone over direct LAN UDP on port 5004"
echo "  Output: $DEVICE"
echo "  Mode  : jam / ~20 ms receive buffer"
echo
echo "Leave this window open while using the iPhone as a microphone."
echo "Press Ctrl-C to stop."
echo

exec "$BIN" \
  --rx \
  --device "$DEVICE" \
  --port 5004 \
  --rate 48000 \
  --channels 2 \
  --codec pcm \
  --mode jam \
  --no-relay \
  --no-auto-tune
