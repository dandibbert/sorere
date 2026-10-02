#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/solunad"
DEVICE="BlackHole 2ch"

if [[ ! -x "$BIN" ]]; then
  echo "TestBlackHole: solunad is missing next to this script."
  exit 1
fi

DEVICES="$("$BIN" --list-devices 2>&1 || true)"
if ! printf '%s\n' "$DEVICES" | grep -Fq "$DEVICE"; then
  echo "TestBlackHole: '$DEVICE' was not found."
  printf '%s\n' "$DEVICES"
  exit 2
fi

echo "Sorere BlackHole self-test"
echo "Generating a 440 Hz tone directly into BlackHole 2ch."
echo
echo "Open QuickTime -> New Audio Recording -> BlackHole 2ch."
echo "Its level meter should move immediately."
echo "Press Ctrl-C to stop."
echo

export SOLUNA_SINE_TEST=1
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
