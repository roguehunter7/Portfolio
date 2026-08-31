#!/usr/bin/env bash
# Render resume.html -> PDF with headless Chrome (preinstalled on GitHub runners).
# Usage: bash scripts/render-pdf.sh [input.html] [output.pdf]
set -euo pipefail

INPUT="${1:-site/resume.html}"
OUTPUT="${2:-site/resume.pdf}"

# ---- Locate a Chrome/Chromium binary (no installs) ----
CHROME=""
for c in google-chrome google-chrome-stable chromium chromium-browser chrome; do
  if command -v "$c" >/dev/null 2>&1; then
    CHROME="$c"
    break
  fi
done
if [ -z "$CHROME" ]; then
  echo "error: no Chrome/Chromium binary found on PATH" >&2
  exit 1
fi

# ---- Render ----
UDD="$(mktemp -d)"
trap 'rm -rf "$UDD"' EXIT
"$CHROME" --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer \
  --user-data-dir="$UDD" \
  --virtual-time-budget=10000 \
  --print-to-pdf="$OUTPUT" \
  "file://$(pwd)/$INPUT"

[ -s "$OUTPUT" ] || { echo "FAIL: $OUTPUT not produced" >&2; exit 1; }

echo "OK: $OUTPUT rendered"
