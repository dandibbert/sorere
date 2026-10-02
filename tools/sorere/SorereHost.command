#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/solunad"
DEVICE="BlackHole 2ch"

if [[ ! -x "$BIN" ]]; then
  echo "Sorere Host is incomplete: solunad is missing."
  exit 1
fi

DEVICES="$("$BIN" --list-devices 2>&1 || true)"
if ! printf '%s\n' "$DEVICES" | grep -Fq "$DEVICE"; then
  echo "Sorere Host could not find BlackHole 2ch."
  echo "Install BlackHole 2ch, then run this again."
  exit 2
fi

echo "Sorere Host"
echo "BlackHole: found"
echo "Waiting for iPhone…"
echo
echo "When the iPhone starts sending, this window will say:"
echo "  iPhone audio received"
echo
echo "Press Ctrl-C to stop."
echo

export SORERE_HOST_MODE=1

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
    /\[SorereHost\] iPhone audio stream received/ {
      print "iPhone audio received"; fflush(); next
    }
    /Error:|Failed|failed|cannot open|not found/ {
      print; fflush()
    }
  '
