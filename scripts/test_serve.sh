#!/usr/bin/env bash
# Smoke-test the Ray Serve FastAPI endpoints using curl.
# Usage: SERVE_URL=http://127.0.0.1:8000 ./scripts/test_serve.sh /path/to/frame.jpg

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: ${0##*/} <image_path>" >&2
  exit 1
fi

IMAGE_PATH="$1"
SERVE_URL="${SERVE_URL:-http://127.0.0.1:8000}"

if [ ! -f "$IMAGE_PATH" ]; then
  echo "Image not found: $IMAGE_PATH" >&2
  exit 2
fi

format_json() {
  if command -v jq >/dev/null 2>&1; then
    jq '.'
  else
    cat
  fi
}

echo "[test-serve] Hitting $SERVE_URL/health"
curl -sf "$SERVE_URL/health" | format_json

echo "[test-serve] Posting to /detect-json"
curl -sf -X POST -F "file=@$IMAGE_PATH" "$SERVE_URL/detect-json" | format_json

tmpfile=$(mktemp /tmp/annotated.XXXXXX.jpg)
cleanup() {
  rm -f "$tmpfile"
}
trap cleanup EXIT

echo "[test-serve] Posting to /detect-image"
curl -sf -X POST -F "file=@$IMAGE_PATH" "$SERVE_URL/detect-image" -o "$tmpfile"

if command -v file >/dev/null 2>&1; then
  file "$tmpfile"
else
  echo "Annotated output saved to $tmpfile"
fi

echo "[test-serve] Success"
