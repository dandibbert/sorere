#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/solunad"
DEVICE="BlackHole 2ch"

if [[ ! -x "$BIN" ]]; then
  echo "BlackHole test is incomplete: solunad is missing."
  exit 1
fi

DEVICES="$("$BIN" --list-devices 2>&1 || true)"
if ! printf '%s\n' "$DEVICES" | grep -Fq "$DEVICE"; then
  echo "BlackHole 2ch was not found."
  exit 2
fi

echo "BlackHole test"
echo
echo "Open QuickTime -> New Audio Recording"
echo "Choose: BlackHole 2ch"
echo
echo "A test tone is being sent now."
echo "The QuickTime level meter should move."
echo
echo "Press Ctrl-C to stop."
echo

export SORERE_HOST_MODE=1
export SOLUNA_SINE_TEST=1

"$BIN" \
  --rx \
  --device "$DEVICE" \
  --port 5004 \
  --rate 48000 \
  --channels 2 \
  --codec pcm \
  --mode jam \
  --no-relay \
  --no-auto-tune \
  2>&1 | awk '
    /\[SorereHost\] BlackHole output ready/ {
      print "BlackHole output ready"; fflush(); next
    }
    /Error:|Failed|failed|cannot open|not found/ {
      print; fflush()
    }
  '
