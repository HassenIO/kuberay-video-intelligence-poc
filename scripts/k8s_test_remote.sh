#!/usr/bin/env bash
# Port-forward Ray Serve temporarily and run the standard HTTP smoke tests.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: ${0##*/} <image_path>" >&2
  exit 1
fi

IMAGE_PATH="$1"
NAMESPACE="${NAMESPACE:-ray-system}"
LOCAL_PORT="${LOCAL_PORT:-18000}"

serve_svc=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep 'serve-svc' | head -n 1 || true)
if [[ -z "$serve_svc" ]]; then
  echo "Could not find serve service in namespace $NAMESPACE" >&2
  exit 2
fi

echo "Port-forwarding svc/$serve_svc to localhost:$LOCAL_PORT"
kubectl port-forward -n "$NAMESPACE" svc/"$serve_svc" "$LOCAL_PORT":8000 >/tmp/serve-test-port-forward.log 2>&1 &
PF_PID=$!

cleanup() {
  kill "$PF_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 3

SERVE_URL="http://127.0.0.1:$LOCAL_PORT" ./scripts/test_serve.sh "$IMAGE_PATH"

echo "Remote smoke test completed"
