#!/usr/bin/env bash
set -euo pipefail

namespace="default"
host="http://booking-service.default.svc.cluster.local"

echo "[INFO] Checking feature flag routing..."

headers="$(
  kubectl exec -n "${namespace}" istio-client -c istio-client -- \
    curl -sS -D - -o /dev/null \
    -H 'X-Feature-Enabled: true' \
    "${host}/feature" \
    | tr -d '\r'
)"

printf '%s\n' "${headers}"

if ! printf '%s\n' "${headers}" | grep -q '^HTTP/.* 200'; then
  echo "[FAIL] Expected HTTP 200 for /feature with X-Feature-Enabled: true"
  exit 1
fi

if ! printf '%s\n' "${headers}" | grep -qi '^X-Booking-Version: v2$'; then
  echo "[FAIL] Expected X-Booking-Version: v2 for feature-flagged request"
  exit 1
fi

body="$(
  kubectl exec -n "${namespace}" istio-client -c istio-client -- \
    curl -sS \
    -H 'X-Feature-Enabled: true' \
    "${host}/feature"
)"

printf '%s\n' "${body}"

if [ "${body}" != "Feature X is enabled!" ]; then
  echo "[FAIL] Unexpected /feature body: ${body}"
  exit 1
fi

echo "[PASS] Feature flag request is routed to v2 and returns enabled body"
