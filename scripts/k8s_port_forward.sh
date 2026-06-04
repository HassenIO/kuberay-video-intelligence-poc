#!/usr/bin/env bash
# Port-forward Ray Serve (8000) and Ray dashboard (8265) services.

set -euo pipefail

NAMESPACE="${NAMESPACE:-ray-system}"
SERVE_LOCAL_PORT="${SERVE_LOCAL_PORT:-8000}"
DASH_LOCAL_PORT="${DASH_LOCAL_PORT:-8265}"

serve_svc=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep 'serve-svc' | head -n 1 || true)
head_svc=$(kubectl get svc -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep 'head-svc' | head -n 1 || true)

if [[ -z "$serve_svc" ]]; then
  echo "Could not find serve service (name containing 'serve-svc') in $NAMESPACE" >&2
  exit 1
fi

if [[ -z "$head_svc" ]]; then
  echo "Could not find head service (name containing 'head-svc') in $NAMESPACE" >&2
  exit 1
fi

echo "Forwarding serve service $serve_svc to localhost:$SERVE_LOCAL_PORT"
kubectl port-forward -n "$NAMESPACE" svc/"$serve_svc" "$SERVE_LOCAL_PORT":8000 >/tmp/serve-port-forward.log 2>&1 &
SERVE_PID=$!

echo "Forwarding head service $head_svc (dashboard) to localhost:$DASH_LOCAL_PORT"
kubectl port-forward -n "$NAMESPACE" svc/"$head_svc" "$DASH_LOCAL_PORT":8265 >/tmp/head-port-forward.log 2>&1 &
DASH_PID=$!

cleanup() {
  echo "Stopping port-forwards"
  kill "$SERVE_PID" "$DASH_PID" >/dev/null 2>&1 || true
}

trap cleanup EXIT

echo "Serve endpoint available at http://127.0.0.1:$SERVE_LOCAL_PORT"
echo "Dashboard available at http://127.0.0.1:$DASH_LOCAL_PORT"
echo "Press Ctrl+C to stop. Logs: /tmp/serve-port-forward.log, /tmp/head-port-forward.log"

wait
