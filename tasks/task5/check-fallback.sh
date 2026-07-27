#!/usr/bin/env bash
set -euo pipefail

namespace="default"
host="http://booking-service.default.svc.cluster.local"

echo "[INFO] Verifying that /fallback-test fails on v1..."
direct_v1_response="$(
  kubectl exec -n "${namespace}" istio-client -c istio-client -- \
    curl -sS -D - -o - \
    -H 'X-Direct-Version: v1' \
    "${host}/fallback-test" \
    | tr -d '\r'
)"

printf '%s\n' "${direct_v1_response}"

if ! printf '%s\n' "${direct_v1_response}" | grep -q '^HTTP/.* 503'; then
  echo "[FAIL] Direct request to v1 must return HTTP 503"
  exit 1
fi

if ! printf '%s\n' "${direct_v1_response}" | grep -qi '^X-Booking-Version: v1$'; then
  echo "[FAIL] Direct request to v1 must return X-Booking-Version: v1"
  exit 1
fi

if ! printf '%s\n' "${direct_v1_response}" | grep -q 'fallback test forced failure from v1'; then
  echo "[FAIL] Direct request to v1 must return the controlled failure body"
  exit 1
fi

echo "[INFO] Verifying automatic fallback from v1 to v2 in a single client request..."
fallback_response="$(
  kubectl exec -n "${namespace}" istio-client -c istio-client -- \
    curl -sS -D - -o - \
    -H 'X-Fallback-Test: true' \
    "${host}/fallback-test" \
    | tr -d '\r'
)"

printf '%s\n' "${fallback_response}"

if ! printf '%s\n' "${fallback_response}" | grep -q '^HTTP/.* 200'; then
  echo "[FAIL] Fallback request must return HTTP 200"
  exit 1
fi

if ! printf '%s\n' "${fallback_response}" | grep -qi '^X-Booking-Version: v2$'; then
  echo "[FAIL] Fallback request must be served by v2"
  exit 1
fi

if ! printf '%s\n' "${fallback_response}" | grep -qi '^X-Fallback-From: v1$'; then
  echo "[FAIL] Fallback response must contain X-Fallback-From: v1"
  exit 1
fi

if ! printf '%s\n' "${fallback_response}" | grep -qi '^X-Fallback-Reason: upstream-503$'; then
  echo "[FAIL] Fallback response must contain X-Fallback-Reason: upstream-503"
  exit 1
fi

if ! printf '%s\n' "${fallback_response}" | grep -q 'fallback test served by v2'; then
  echo "[FAIL] Fallback response must contain the v2 success body"
  exit 1
fi

echo "[PASS] Automatic fallback v1 -> v2 works for /fallback-test"
