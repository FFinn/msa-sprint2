#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RESULTS_DIR="${SCRIPT_DIR}/results"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-40}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

mkdir -p "${RESULTS_DIR}"
exec > >(tee "${RESULTS_DIR}/test-log.txt") 2>&1

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
  echo "${label} did not become ready" >&2
  return 1
}

wait_for_grpc() {
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    if docker compose exec -T booking-service python /app/grpc_client.py list >/dev/null 2>&1; then
      echo "ready: grpc booking-service (${attempt}/${MAX_ATTEMPTS})"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done
  echo "grpc booking-service did not become ready" >&2
  return 1
}

echo "# Task 2 collect results"
date '+Date: %Y-%m-%d %H:%M:%S %z'

if ! docker network inspect hotelio-net >/dev/null 2>&1; then
  run_cmd docker network create hotelio-net
fi

wait_for_http "http://localhost:8084/api/bookings?userId=" "monolith REST facade"
wait_for_grpc

run_cmd docker compose ps
run_cmd ./results/regress.sh

docker compose ps > "${RESULTS_DIR}/docker-ps.txt"
docker compose logs --no-color monolith | rg 'BookingService beans:|bookingService:|grpcBookingService:' \
  > "${RESULTS_DIR}/monolith-logs.txt"

curl -sSf "http://localhost:8084/api/bookings?userId=" | python3 -m json.tool \
  > "${RESULTS_DIR}/monolith-bookings.json"

docker compose exec -T booking-service python /app/grpc_client.py list \
  > "${RESULTS_DIR}/grpc-bookings.txt"

docker compose exec -T monolith-db psql -U hotelio -d hotelio -c \
  'SELECT id, user_id, hotel_id, promo_code, discount_percent, price, created_at FROM booking ORDER BY id;' \
  > "${RESULTS_DIR}/monolith-booking-db.txt"

docker compose exec -T booking-db psql -U hotelio -d bookings -c \
  'SELECT id, user_id, hotel_id, promo_code, discount_percent, price, created_at FROM bookings ORDER BY id;' \
  > "${RESULTS_DIR}/booking-db.txt"

docker compose exec -T booking-history-db psql -U hotelio -d booking_history -c \
  'SELECT booking_id, user_id, hotel_id, promo_code, discount_percent, price, created_at, received_at FROM booking_history ORDER BY booking_id;' \
  > "${RESULTS_DIR}/booking-history-db.txt"

echo "Artifacts written to ${RESULTS_DIR}"
