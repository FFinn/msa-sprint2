#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASK_DIR="${SCRIPT_DIR}"
LOG_FILE="${TASK_DIR}/results/test-log.txt"
API_BASE="http://localhost:8084"
MAX_ATTEMPTS=30
SLEEP_SECONDS=2
TEST_DIR="../../test"

cd "${TASK_DIR}"

run_cmd() {
  echo
  echo "$ $*"
  "$@"
}

wait_for_api() {
  echo
  echo "$ readiness probe: bounded retry for ${API_BASE}/api/bookings"
  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    if curl -fsS "${API_BASE}/api/bookings" >/dev/null 2>&1; then
      echo "API ready on attempt ${attempt}/${MAX_ATTEMPTS}"
      return 0
    fi
    sleep "${SLEEP_SECONDS}"
  done

  echo "API did not become ready after ${MAX_ATTEMPTS} attempts" >&2
  return 1
}

mkdir -p "${TASK_DIR}/results"
exec > >(tee "${LOG_FILE}") 2>&1

echo "# Task 1 verification"
date '+Date: %Y-%m-%d %H:%M:%S %z'

if ! docker network inspect hotelio-net >/dev/null 2>&1; then
  run_cmd docker network create hotelio-net
fi
run_cmd docker compose down --volumes --remove-orphans

run_cmd docker compose up -d --build
wait_for_api

echo
echo "$ docker compose exec -T monolith-db psql -U hotelio -d hotelio < ${TEST_DIR}/init-fixtures.sql"
docker compose exec -T monolith-db psql -U hotelio -d hotelio < "${TEST_DIR}/init-fixtures.sql"

run_cmd curl -sSf -X POST "${API_BASE}/api/bookings?userId=test-user-3&hotelId=test-hotel-1"
run_cmd curl -sSf "${API_BASE}/api/bookings"

run_cmd docker build -t hotelio-tester "${TEST_DIR}"
run_cmd docker run --rm \
  --network hotelio-net \
  -e DB_HOST=hotelio-db \
  -e DB_PORT=5432 \
  -e DB_NAME=hotelio \
  -e DB_USER=hotelio \
  -e DB_PASSWORD=hotelio \
  -e API_URL=http://hotelio-monolith:8080 \
  hotelio-tester

run_cmd docker compose ps
run_cmd docker compose logs --no-color --tail=100
