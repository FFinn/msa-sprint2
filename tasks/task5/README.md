# Задание 5

В этом задании используется тот же `booking-service`, что и в задании 4, но уже
в Kubernetes с Istio.

Сервис разворачивается в двух версиях:

- `v1` — основная версия, `ENABLE_FEATURE_X=false`, `SERVICE_VERSION=v1`, `FALLBACK_TEST_MODE=fail`;
- `v2` — новая версия, `ENABLE_FEATURE_X=true`, `SERVICE_VERSION=v2`, `FALLBACK_TEST_MODE=success`.

Обе версии работают за одним Kubernetes Service `booking-service`. Дальше
распределением трафика между ними управляет Istio.

## Подготовка

```bash
cd tasks/task5
go test ./booking-service/...
docker build -t booking-service:latest ./booking-service
minikube image load booking-service:latest
```

## Установка Istio

Если `istioctl` ещё не установлен:

```bash
curl -L https://istio.io/downloadIstio | sh -
export PATH="$PWD"/istio-*/bin:$PATH
```

Установка Istio и включение автоматической инъекции sidecar-прокси в
пространстве имён `default`:

```bash
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled --overwrite
```

## Развёртывание

Если в `default` остался релиз `booking-service` из задания 4, его нужно
удалить, иначе он будет конфликтовать с общим Service `booking-service`:

```bash
helm uninstall booking-service -n default
```

Дальше развёртывание выполняется так:

```bash
kubectl apply -f kubernetes/service.yaml

helm upgrade --install booking-service-v1 helm/booking-service \
  --namespace default \
  -f values-v1.yaml

helm upgrade --install booking-service-v2 helm/booking-service \
  --namespace default \
  -f values-v2.yaml

kubectl apply -f kubernetes/istio-client.yaml
kubectl apply -f istio/destination-rule.yaml
kubectl apply -f istio/virtual-service.yaml
kubectl apply -f istio/envoy-filter.yaml
```

После этого нужно дождаться готовности клиента и обеих версий сервиса:

```bash
kubectl wait --for=condition=Ready pod/istio-client --timeout=120s
kubectl rollout status deployment/booking-service-v1 --timeout=180s
kubectl rollout status deployment/booking-service-v2 --timeout=180s
```

## Как устроена маршрутизация

### Канареечное распределение

Обычный трафик распределяется через `VirtualService` так:

- `90%` запросов идут в `v1`;
- `10%` запросов идут в `v2`.

### Флаг функции

Проверочный клиент — это Pod `istio-client`. На его исходящем встроенном прокси (sidecar)
применяется `EnvoyFilter`, который:

- читает заголовок `X-Feature-Enabled: true`;
- добавляет внутренний заголовок `x-istio-feature-route: v2`;
- вызывает `clearRouteCache()`, чтобы маршрут был пересчитан.

После этого `VirtualService` направляет такой запрос целиком в `v2`.

### Поведение при сбоях

В решении используются два уровня защиты:

- `VirtualService` задаёт политику повторных попыток;
- `DestinationRule` задаёт ограничения соединений и временное исключение
  проблемных экземпляров из балансировки.

Для отдельного маршрута `/fallback-test` реализован управляемый сценарий
автоматического переключения (fallback):

- `v1` на `/fallback-test` всегда отвечает `503`;
- `v2` на `/fallback-test` отвечает `200`;
- клиентский `EnvoyFilter` для `istio-client` для запроса `GET /fallback-test`
  с заголовком `X-Fallback-Test: true` сначала вызывает подмножество `v1`;
- если `v1` возвращает `5xx`, тот же запрос внутри прокси автоматически
  переключается на подмножество `v2`;
- клиент получает ответ `v2` с диагностическими заголовками
  `X-Fallback-From: v1` и `X-Fallback-Reason`.

Это отдельный тестовый маршрут, который не влияет на обычное канареечное распределение `90/10` и не
мешает флагу функции. Универсальное автоматическое переключение для любых методов и маршрутов
здесь не заявляется.

## Проверочные скрипты

```bash
./check-istio.sh
./check-canary.sh
./check-feature-flag.sh
./check-fallback.sh
```

Проверочные запросы отправляются из `istio-client` на внутренний адрес сервиса
в сети Istio:

```bash
http://booking-service.default.svc.cluster.local
```

Проверять маршрутизацию через `kubectl port-forward` здесь не нужно: такой
запрос идёт напрямую в Pod и обходит межсервисную маршрутизацию Istio.
