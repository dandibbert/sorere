#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/sorere-host"

if [[ ! -x "$BIN" ]]; then
  echo "Sorere Host is incomplete: sorere-host is missing."
  exit 1
fi

echo "Sorere Host"
echo
exec "$BIN"
