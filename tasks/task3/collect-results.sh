#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RESULTS_DIR="${SCRIPT_DIR}/results"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-40}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

mkdir -p "${RESULTS_DIR}"
rm -f \
  "${RESULTS_DIR}/docker-ps.txt" \
  "${RESULTS_DIR}/test-log.txt" \
  "${RESULTS_DIR}/graphql-allowed.json" \
  "${RESULTS_DIR}/graphql-denied.json" \
  "${RESULTS_DIR}/compose.log" \
  "${RESULTS_DIR}/graphql-allowed.png" \
  "${RESULTS_DIR}/graphql-denied.png"
exec > >(tee "${RESULTS_DIR}/test-log.txt") 2>&1

pass() {
  echo "✅ $1"
}

fail() {
  echo "❌ $1"
  exit 1
}

wait_for_monolith() {
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    code="$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8084/api/hotels/does-not-exist || true)"
    if [ "${code}" = "404" ] || [ "${code}" = "200" ]; then
      echo "ready: monolith REST (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "monolith REST did not become ready"
}

wait_for_gateway() {
  local probe='{"query":"query { __typename }"}'
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    response="$(curl -sS http://localhost:4000/ -H 'content-type: application/json' --data "${probe}" || true)"
    if jq -e '.errors == null and .data.__typename == "Query"' >/dev/null 2>&1 <<<"${response}"; then
      echo "ready: apollo-gateway (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "apollo-gateway did not become ready"
}

wait_for_healthy() {
  local service="$1"
  local container_id
  container_id="$(docker compose ps -q "${service}")"
  [ -n "${container_id}" ] || fail "service ${service} does not have a running container"

  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "${container_id}")"
    if [ "${status}" = "healthy" ]; then
      echo "healthy: ${service} (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    if [ "${status}" = "unhealthy" ]; then
      fail "service ${service} became unhealthy"
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "service ${service} did not become healthy"
}

echo "# Task 3 collect results"
date '+Date: %Y-%m-%d %H:%M:%S %z'
echo "Assumption: services were started from a clean state with 'docker compose down --volumes --remove-orphans'."

wait_for_monolith
echo
echo "$ docker compose exec -T monolith-db psql -U hotelio -d hotelio < monolith-fixtures.sql"
docker compose exec -T monolith-db psql -U hotelio -d hotelio < monolith-fixtures.sql
pass "Applied monolith fixture for hotel h1"

wait_for_gateway
wait_for_healthy apollo-gateway
wait_for_healthy booking-subgraph
wait_for_healthy hotel-subgraph
wait_for_healthy booking-service
wait_for_healthy booking-db
wait_for_healthy monolith

query='query { bookingsByUser(userId: "user1") { id userId hotelId promoCode discountPercent hotel { name city } } }'
payload="$(jq -nc --arg query "${query}" '{query: $query}')"

allowed_response="$(curl -sS http://localhost:4000/ \
  -H 'content-type: application/json' \
  -H 'userid: user1' \
  --data "${payload}")"
printf '%s\n' "${allowed_response}" | jq . > "${RESULTS_DIR}/graphql-allowed.json"

jq -e '
  .errors == null and
  (.data.bookingsByUser | type == "array") and
  (.data.bookingsByUser | length > 0) and
  (.data.bookingsByUser[0].hotel.name | type == "string") and
  (.data.bookingsByUser[0].hotel.name | length > 0) and
  (.data.bookingsByUser[0].hotel.city | type == "string") and
  (.data.bookingsByUser[0].hotel.city | length > 0)
' "${RESULTS_DIR}/graphql-allowed.json" >/dev/null
pass "Allowed GraphQL query returned booking with federated hotel fields"

denied_response="$(curl -sS http://localhost:4000/ \
  -H 'content-type: application/json' \
  -H 'userid: user2' \
  --data "${payload}")"
printf '%s\n' "${denied_response}" | jq . > "${RESULTS_DIR}/graphql-denied.json"

jq -e '
  .errors == null and
  .data.bookingsByUser == []
' "${RESULTS_DIR}/graphql-denied.json" >/dev/null
pass "Denied GraphQL query returned empty list because of ACL"

docker compose logs --no-color apollo-gateway booking-subgraph hotel-subgraph > "${RESULTS_DIR}/compose.log"

grep -q 'Возвращено бронирований:' "${RESULTS_DIR}/compose.log" || fail "booking-subgraph success log not found"
grep -q 'Доступ к бронированиям user1 отклонён' "${RESULTS_DIR}/compose.log" || fail "booking-subgraph ACL deny log not found"
grep -q 'Resolved hotel h1 from monolith REST' "${RESULTS_DIR}/compose.log" || fail "hotel-subgraph REST resolve log not found"
if grep -q 'serviceList' "${RESULTS_DIR}/compose.log"; then
  fail "compose.log still contains deprecated serviceList warning"
fi
pass "Subgraph logs confirm success, ACL deny and real hotel REST resolve"

docker compose ps > "${RESULTS_DIR}/docker-ps.txt"

pass "Artifacts written to ${RESULTS_DIR}"
