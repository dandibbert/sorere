#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/sorere-host"

if [[ ! -x "$BIN" ]]; then
  echo "BlackHole test is incomplete: sorere-host is missing."
  exit 1
fi

echo "BlackHole self-test"
echo
echo "This test does not use the iPhone or Wi-Fi."
echo "It writes a tone to BlackHole and checks whether BlackHole returns it as input."
echo
exec "$BIN" --test-tone
