# Задание 4

## Что делает сервис

`booking-service` в этом задании — демонстрационный HTTP-сервис для проверки Docker,
Helm, GitLab CI/CD и Kubernetes DNS.

Маршруты:

- `GET /ping` -> `200` и тело `pong`
- `GET /health` -> `200`
- `GET /ready` -> `200`
- `GET /feature`:
  - при `ENABLE_FEATURE_X=true` -> `200` и тело `Feature X is enabled!`
  - иначе -> `404`

## Локальная сборка и запуск

```bash
cd tasks/task4
go test ./booking-service/...
docker build -t booking-service:latest ./booking-service
docker run --rm -p 8080:8080 booking-service:latest
```

Проверка:

```bash
curl http://localhost:8080/ping
curl http://localhost:8080/health
curl http://localhost:8080/ready
curl -i http://localhost:8080/feature
```

Запуск с включённым флагом функции:

```bash
docker run --rm -p 8080:8080 -e ENABLE_FEATURE_X=true booking-service:latest
curl http://localhost:8080/feature
```

## Minikube

```bash
minikube start --driver=docker
export NAMESPACE=default
```

## Helm

Предпродакшн:

```bash
minikube image load booking-service:latest
helm upgrade --install booking-service helm/booking-service \
  --namespace "${NAMESPACE}" \
  -f values-staging.yaml
```

Промышленная среда:

```bash
minikube image load booking-service:latest
helm upgrade --install booking-service helm/booking-service \
  --namespace "${NAMESPACE}" \
  -f values-prod.yaml
```

В текущем варианте предпродакшн и промышленная среда используют один и тот же Helm-релиз
`booking-service` в одном пространстве имён Kubernetes. Это значит, что запуск команды
для промышленной среды обновит предпродакшн-развёртывание.

Если нужно проверять оба варианта одновременно, используйте разные имена релизов
или разные пространства имён Kubernetes, например:

```bash
minikube image load booking-service:latest
helm upgrade --install booking-service-staging helm/booking-service \
  --namespace staging \
  -f values-staging.yaml

minikube image load booking-service:latest
helm upgrade --install booking-service-prod helm/booking-service \
  --namespace production \
  -f values-prod.yaml
```

Для локальной разработки предпродакшн-стенд использует:

- образ `booking-service:latest`
- `image.pullPolicy: Never`

После сборки локального образа его нужно загрузить в Minikube:

```bash
minikube image load booking-service:latest
```

## Проверка статуса

```bash
./check-status.sh
```

Локальная проверка через перенаправление порта:

```bash
kubectl port-forward -n "${NAMESPACE}" svc/booking-service 8080:80
curl http://localhost:8080/ping
```

## Проверка DNS внутри кластера

```bash
./check-dns.sh
```

DNS-имя `booking-service` работает только внутри Kubernetes-кластера. С хоста
используется `kubectl port-forward`.

Во всех командах задания 4 используется единое пространство имён Kubernetes через переменную
окружения `NAMESPACE`. По умолчанию скрипты ожидают `default`.

## Helm-проверки

```bash
helm lint helm/booking-service -f values-staging.yaml
helm lint helm/booking-service -f values-prod.yaml
helm template booking-service helm/booking-service -f values-staging.yaml
helm template booking-service helm/booking-service -f values-prod.yaml
```

## GitLab CI/CD локально

```bash
gitlab-ci-local unit build test deploy tag
```

Конвейер предполагает runner с доступом к `docker`, `kubectl`, `helm`,
`minikube` и `gitlab-ci-local`. Docker Registry не используется: образ
передаётся между задачами через `docker save` / `docker load`, а в Minikube
загружается через `minikube image load`.

Конвейер выполняет:

1. `unit` -> `go test ./...`
2. `build` -> `docker build` + `docker save`
3. `test` -> `docker load`, `docker run` и HTTP-проверки `/ping`, `/health`, `/ready`, `/feature`
4. `deploy` -> `docker load`, `minikube image load` + `helm upgrade --install`
5. `tag` -> создаёт локальный git-тег с отметкой времени UTC без отправки в удалённый репозиторий
