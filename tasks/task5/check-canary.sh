#!/usr/bin/env bash
set -euo pipefail

namespace="default"
host="http://booking-service.default.svc.cluster.local/ping"
requests="${1:-100}"
v1=0
v2=0

echo "[INFO] Checking canary distribution with ${requests} requests..."

for _ in $(seq 1 "${requests}"); do
  version="$(
    kubectl exec -n "${namespace}" istio-client -c istio-client -- \
      curl -fsS -D - -o /dev/null "${host}" \
      | tr -d '\r' \
      | awk -F': ' 'tolower($1) == "x-booking-version" {print $2}'
  )"

  case "${version}" in
    v1) v1=$((v1 + 1)) ;;
    v2) v2=$((v2 + 1)) ;;
    *)
      echo "[FAIL] Unexpected X-Booking-Version: ${version:-<empty>}"
      exit 1
      ;;
  esac
done

echo "[INFO] v1=${v1}, v2=${v2}"

if [ "${v1}" -le 0 ] || [ "${v2}" -le 0 ]; then
  echo "[FAIL] Expected both subsets to receive traffic"
  exit 1
fi

if [ "${requests}" -eq 100 ]; then
  if [ "${v2}" -lt 5 ] || [ "${v2}" -gt 25 ]; then
    echo "[FAIL] v2 count ${v2} is outside expected canary range [5, 25] for 100 requests"
    exit 1
  fi
fi

echo "[PASS] Canary distribution is within the expected range"
