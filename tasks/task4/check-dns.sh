#!/usr/bin/env bash
set -euo pipefail

namespace="${NAMESPACE:-default}"

pod_name="dns-test-$(date +%s)-$$"

echo "[INFO] Running in-cluster DNS test..."
raw_output="$(
  kubectl run "${pod_name}" \
    --namespace "${namespace}" \
    --rm -i \
    --restart=Never \
    --image=busybox:1.36 \
    --command -- sh -ec 'wget -T 5 -qO- http://booking-service/ping; printf "\n"'
)"
response="$(printf '%s\n' "${raw_output}" | awk 'NR==1 {print; exit}')"

echo "[INFO] DNS Response: ${response}"

if [ "${response}" != "pong" ]; then
  echo "[FAIL] Expected pong but got: ${response}"
  exit 1
fi

echo "[PASS] DNS test succeeded"
