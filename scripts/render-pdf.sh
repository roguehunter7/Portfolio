#!/usr/bin/env bash
# Render resume.html -> PDF with headless Chrome (preinstalled on GitHub runners),
# then assert ATS-safety: exactly 1 page and key text extractable (the copy-paste test).
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

# ---- poppler-utils for assertions (install only if missing) ----
if ! command -v pdfinfo >/dev/null 2>&1 || ! command -v pdftotext >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y -qq poppler-utils
  else
    echo "WARN: pdfinfo/pdftotext unavailable — skipping ATS assertions" >&2
    exit 0
  fi
fi

# ---- Assertion 1: single page ----
PAGES="$(pdfinfo "$OUTPUT" | awk '/^Pages:/{print $2}')"
if [ "$PAGES" != "1" ]; then
  echo "FAIL: expected 1 page, got $PAGES — tune resume.css" >&2
  exit 1
fi

# ---- Assertion 2: ATS text extraction (copy-paste test) ----
TEXT="$(pdftotext "$OUTPUT" -)"
for s in "Sreeram K R" "contact.sreeramkr@gmail.com" "Professional Summary" \
         "Technical Skills" "Professional Experience" "Certifications" "Education"; do
  if ! grep -qiF "$s" <<<"$TEXT"; then
    echo "FAIL: '$s' not extractable from PDF (ATS risk)" >&2
    exit 1
  fi
done

# ---- Assertion 3: ATS parse order (sections must extract in document order) ----
LAST=0
for s in "Professional Summary" "Technical Skills" "Technical Projects" \
         "Professional Experience" "Certifications" "Education"; do
  LINE="$(grep -niF "$s" <<<"$TEXT" | head -1 | cut -d: -f1)"
  if [ -z "$LINE" ]; then
    echo "FAIL: section '$s' not found in PDF text" >&2
    exit 1
  fi
  if [ "$LINE" -le "$LAST" ]; then
    echo "FAIL: section '$s' extracts at line $LINE (previous $LAST) — out of order, ATS parse risk" >&2
    exit 1
  fi
  LAST="$LINE"
done

echo "OK: $OUTPUT rendered ($PAGES page, ATS text + section order verified)"
