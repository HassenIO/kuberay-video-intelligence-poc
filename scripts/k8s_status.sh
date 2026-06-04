#!/usr/bin/env bash
# Quick status report for the RayService deployment on Kubernetes.

set -euo pipefail

NAMESPACE="${NAMESPACE:-ray-system}"

echo "[k8s-status] Namespace: $NAMESPACE"

echo "\nPods:"
kubectl get pods -n "$NAMESPACE" -o wide

echo "\nServices:"
kubectl get svc -n "$NAMESPACE"

echo "\nRayService objects:"
kubectl get rayservice -n "$NAMESPACE"

echo "\nApplication status snippet:"
kubectl get rayservice video-intelligence-service -n "$NAMESPACE" -o jsonpath='{.status.applicationStatuses}' || true
echo
