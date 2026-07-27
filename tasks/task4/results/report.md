# Отчёт по заданию 4

## Что реализовано

- HTTP-сервис `booking-service` на Go слушает порт `8080`.
- Реализованы маршруты:
  - `GET /ping` -> `200` и тело `pong`
  - `GET /health` -> `200`
  - `GET /ready` -> `200`
  - `GET /feature` -> `200` и `Feature X is enabled!` только при `ENABLE_FEATURE_X=true`
  - `GET /feature` -> `404` при выключенном или отсутствующем флаге
- Роутер вынесен в отдельную функцию, добавлены unit-тесты.

## Docker

- Образ собирается командой:
  `docker build -t booking-service:latest ./booking-service`
- Dockerfile использует многоэтапную сборку и не включает лишние файлы из задания 4.
- Сборка бинарника учитывает целевую архитектуру контейнера, поэтому образ
  корректно работает на локальном `arm64` Minikube.

## Helm

- Chart деплоит `Deployment` и `Service` с именем `booking-service`.
- `Service` имеет тип `ClusterIP`, `port: 80`, `targetPort: 8080`.
- `Deployment` использует:
  - `replicaCount`
  - `image.name`, `image.tag`, `image.pullPolicy`
  - `env[]`
  - `ENABLE_FEATURE_X`
  - `resources`
  - `livenessProbe` и `readinessProbe` на `GET /ping`
- Подготовлены:
  - `values-staging.yaml`
  - `values-prod.yaml`

## CI/CD

- Реализован `.gitlab-ci.yml` со стадиями:
  - `unit`
  - `build`
  - `test`
  - `deploy`
  - `tag`
- Полный локальный прогон выполнен командой:
  `gitlab-ci-local unit build test deploy tag`
- Между `build`, `test` и `deploy` образ переносится без registry через
  `docker save` / `docker load` и GitLab artifact `booking-service-image.tar`.
- Deploy использует:
  - `minikube image load`
  - `helm upgrade --install booking-service helm/booking-service -f values-staging.yaml`
  - `kubectl rollout status deployment/booking-service`

## DNS и Kubernetes

- `check-dns.sh` запускает временный pod `busybox` внутри кластера и проверяет,
  что `http://booking-service/ping` возвращает строго `pong`.
- Выполнены:
  - `./check-status.sh`
  - `./check-dns.sh`
  - `kubectl get pods`
  - `kubectl get svc`
  - `kubectl port-forward svc/booking-service 8080:80`
  - `curl http://localhost:8080/ping`

## Артефакты

- `report.md`
- `.gitlab-ci.yml`
- `values-staging.yaml`
- `values-prod.yaml`
- `helm-lint-staging.txt`
- `helm-lint-prod.txt`
- `helm-template-staging.yaml`
- `helm-template-prod.yaml`
- `build-log.txt`
- `status-output.txt`
- `dns-output.txt`
- `kubectl-get-pods-services.txt`
- `image-lists.txt`
- `ping-output.txt`
- `ping-output.png`
- `dns-output.png`
- `status-output.png`
