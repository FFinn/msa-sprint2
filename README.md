# Hotelio — проектная работа второго спринта

Результаты расположены в `tasks/task1/results` — `tasks/task5/results`.

## Задание 1

```bash
cd tasks/task1
./verify.sh
```

Подробная инструкция и результаты находятся в
[tasks/task1/README.md](tasks/task1/README.md).

## Задание 2

```bash
cd tasks/task1 && docker compose down
cd ../task2
docker network create hotelio-net 2>/dev/null || true
docker compose up -d --build
./collect-results.sh
```

После проверки остановите контейнеры: `docker compose down`.

## Задание 3

```bash
cd tasks/task3
docker compose up -d --build
./collect-results.sh
```

`graphql-allowed.json` содержит результат с заголовком `userid: user1`, а
`graphql-denied.json` — тот же запрос с чужим идентификатором.

## Задание 4

```bash
cd tasks/task4
(cd booking-service && go test ./...)
docker build -t booking-service:latest booking-service
minikube start --driver=docker
minikube image load booking-service:latest
helm upgrade --install booking-service helm/booking-service --values values-staging.yaml
./check-status
./check-dns.sh
gitlab-ci-local build test deploy tag
```

## Задание 5

Полная воспроизводимая инструкция, проверочные команды и результаты находятся в
[tasks/task5/README.md](tasks/task5/README.md).
