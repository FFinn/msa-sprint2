#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${TASK_DIR}"

API_BASE="${API_URL:-http://localhost:8084}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

pass() {
  echo "✅ $1"
}

fail() {
  echo "❌ $1"
  exit 1
}

run_cmd() {
  echo
  echo "$ $*"
  "$@"
}

wait_for_http() {
  local url="$1"
  local label="$2"
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      echo "ready: ${label} (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "${label} did not become ready"
}

wait_for_grpc() {
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    if docker compose exec -T booking-service python /app/grpc_client.py list >/dev/null 2>&1; then
      echo "ready: grpc booking-service (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "grpc booking-service did not become ready"
}

wait_for_history_table() {
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    local table_name
    table_name="$(docker compose exec -T booking-history-db psql -U hotelio -d booking_history -tAc \
      "SELECT to_regclass('public.booking_history');")"
    table_name="${table_name//[[:space:]]/}"
    if [ "${table_name}" = "booking_history" ]; then
      echo "ready: booking_history table (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "booking_history table was not created"
}

wait_for_history_count() {
  local expected_count="$1"
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    local count
    count="$(docker compose exec -T booking-history-db psql -U hotelio -d booking_history -tAc \
      'SELECT COUNT(*) FROM booking_history;')"
    count="${count//[[:space:]]/}"
    if [[ "${count}" =~ ^[0-9]+$ ]] && [ "${count}" -ge "${expected_count}" ]; then
      echo "ready: booking_history count=${count} (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  fail "booking_history did not reach ${expected_count} rows"
}

reset_databases() {
  echo "Resetting monolith-db fixtures"
  docker compose exec -T monolith-db psql -U hotelio -d hotelio < ../../test/init-fixtures.sql

  echo "Resetting booking-db fixtures"
  docker compose exec -T booking-db psql -U hotelio -d bookings < booking-fixtures.sql

  echo "Clearing booking-history-db"
  wait_for_history_table
  docker compose exec -T booking-history-db psql -U hotelio -d booking_history -c \
    'TRUNCATE TABLE booking_history;'
}

assert_grpc_failed_precondition() {
  local user_id="$1"
  local hotel_id="$2"
  local description="$3"
  local output

  set +e
  output="$(docker compose exec -T booking-service python /app/grpc_client.py create \
    --user-id "${user_id}" --hotel-id "${hotel_id}" 2>&1)"
  local status=$?
  set -e

  if [ "${status}" -ne 0 ] && grep -q 'FAILED_PRECONDITION' <<<"${output}"; then
    pass "${description}"
    return 0
  fi

  echo "${output}"
  fail "Expected FAILED_PRECONDITION for ${description}"
}

assert_rest_rejected() {
  local url="$1"
  local description="$2"
  local code
  code="$(curl -s -o /dev/null -w "%{http_code}" -X POST "${url}")"
  if [ "${code}" = "500" ]; then
    pass "${description} (current monolith proxy returns HTTP ${code})"
    return 0
  fi
  fail "${description}: expected current monolith proxy HTTP 500, got ${code}"
}

wait_for_http "${API_BASE}/api/bookings?userId=" "monolith REST facade"
wait_for_grpc
reset_databases

echo
echo "User checks..."
curl -sSf "${API_BASE}/api/users/test-user-1" | grep -q 'Alice' \
  && pass "GET /api/users/test-user-1" || fail "User fixture not loaded"
curl -sSf "${API_BASE}/api/users/test-user-1/status" | grep -q 'ACTIVE' \
  && pass "GET /api/users/test-user-1/status" || fail "User status mismatch"
curl -sSf "${API_BASE}/api/users/test-user-1/blacklisted" | grep -q 'true' \
  && pass "GET /api/users/test-user-1/blacklisted" || fail "Blacklist check failed"
curl -sSf "${API_BASE}/api/users/test-user-3/vip" | grep -q 'true' \
  && pass "GET /api/users/test-user-3/vip" || fail "VIP check failed"
curl -sSf "${API_BASE}/api/users/test-user-2/authorized" | grep -q 'true' \
  && pass "GET /api/users/test-user-2/authorized" || fail "Authorization check failed"

echo
echo "Hotel and review checks..."
curl -sSf "${API_BASE}/api/hotels/test-hotel-1/operational" | grep -q 'true' \
  && pass "Hotel operational check" || fail "Hotel operational check failed"
curl -sSf "${API_BASE}/api/hotels/test-hotel-2/fully-booked" | grep -q 'true' \
  && pass "Hotel fully-booked check" || fail "Hotel fully-booked check failed"
curl -sSf "${API_BASE}/api/reviews/hotel/test-hotel-1/trusted" | grep -q 'true' \
  && pass "Trusted hotel check" || fail "Trusted hotel check failed"
curl -sSf "${API_BASE}/api/reviews/hotel/test-hotel-3/trusted" | grep -q 'false' \
  && pass "Untrusted hotel check" || fail "Untrusted hotel check failed"

echo
echo "Promo checks..."
curl -sSf "${API_BASE}/api/promos/TESTCODE1" | grep -q 'TESTCODE1' \
  && pass "GET /api/promos/TESTCODE1" || fail "Promo fixture not loaded"
curl -sSf "${API_BASE}/api/promos/TESTCODE-VIP/valid?isVipUser=true" | grep -q 'true' \
  && pass "VIP promo valid for VIP" || fail "VIP promo validation failed"
curl -sSf "${API_BASE}/api/promos/TESTCODE-VIP/valid?isVipUser=false" | grep -q 'false' \
  && pass "VIP promo rejected for non-VIP" || fail "VIP promo mismatch"
curl -sSf -X POST "${API_BASE}/api/promos/validate?code=TESTCODE1&userId=test-user-2" | grep -q 'TESTCODE1' \
  && pass "POST /api/promos/validate" || fail "Promo validation endpoint failed"

echo
echo "Booking checks through REST facade..."
curl -sSf "${API_BASE}/api/bookings?userId=" | grep -q 'test-user-2' \
  && pass "GET /api/bookings?userId= returns migrated history" || fail "REST list-all through gRPC failed"
curl -sSf "${API_BASE}/api/bookings?userId=test-user-2" | grep -q 'test-user-2' \
  && pass "GET /api/bookings?userId=test-user-2" || fail "REST filtered list through gRPC failed"

success_without_promo="$(curl -sSf -X POST "${API_BASE}/api/bookings?userId=test-user-3&hotelId=test-hotel-1")"
grep -q '"hotelId":"test-hotel-1"' <<<"${success_without_promo}" \
  && pass "REST POST without promo goes through gRPC" || fail "REST POST without promo failed"

success_with_promo="$(curl -sSf -X POST \
  "${API_BASE}/api/bookings?userId=test-user-2&hotelId=test-hotel-1&promoCode=TESTCODE1")"
grep -q '"promoCode":"TESTCODE1"' <<<"${success_with_promo}" \
  && pass "REST POST with promo goes through gRPC" || fail "REST POST with promo failed"

echo
echo "Booking checks direct to gRPC..."
docker compose exec -T booking-service python /app/grpc_client.py list --user-id test-user-2 | grep -q 'test-user-2' \
  && pass "gRPC ListBookings returns user history" || fail "Direct gRPC ListBookings failed"
assert_grpc_failed_precondition "test-user-0" "test-hotel-1" "gRPC rejects inactive user"
assert_grpc_failed_precondition "test-user-2" "test-hotel-3" "gRPC rejects non-operational hotel"
assert_grpc_failed_precondition "test-user-2" "test-hotel-2" "gRPC rejects fully-booked/untrusted hotel"

echo
echo "REST proxy rejection checks..."
assert_rest_rejected "${API_BASE}/api/bookings?userId=test-user-0&hotelId=test-hotel-1" \
  "REST proxy rejects inactive user"
assert_rest_rejected "${API_BASE}/api/bookings?userId=test-user-2&hotelId=test-hotel-3" \
  "REST proxy rejects non-operational hotel"
assert_rest_rejected "${API_BASE}/api/bookings?userId=test-user-2&hotelId=test-hotel-2" \
  "REST proxy rejects fully-booked/untrusted hotel"

wait_for_history_count 2

booking_count="$(docker compose exec -T booking-db psql -U hotelio -d bookings -tAc \
  'SELECT COUNT(*) FROM bookings;')"
booking_count="${booking_count//[[:space:]]/}"
[ "${booking_count}" = "4" ] \
  && pass "booking-db contains 4 rows after two successful creates" \
  || fail "booking-db row count expected 4, got ${booking_count}"

history_count="$(docker compose exec -T booking-history-db psql -U hotelio -d booking_history -tAc \
  'SELECT COUNT(*) FROM booking_history;')"
history_count="${history_count//[[:space:]]/}"
[ "${history_count}" = "2" ] \
  && pass "booking-history-db received 2 async records" \
  || fail "booking-history row count expected 2, got ${history_count}"

echo "✅ Task 2 regression passed"
