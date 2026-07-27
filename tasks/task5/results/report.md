# Отчёт по заданию 5

### Что развёрнуто

Для проверки используется сервис `booking-service` в двух версиях:

- `booking-service-v1` — основная версия, 3 реплики, `SERVICE_VERSION=v1`, `ENABLE_FEATURE_X=false`, `FALLBACK_TEST_MODE=fail`;
- `booking-service-v2` — новая версия, 1 реплика, `SERVICE_VERSION=v2`, `ENABLE_FEATURE_X=true`, `FALLBACK_TEST_MODE=success`.

Обе версии работают за одним Kubernetes Service `booking-service`. Обычные запросы идут через Istio-маршрутизацию между подмножествами `v1` и `v2`.

### Как устроена маршрутизация

В решении используются три основных ресурса Istio:

- `VirtualService` — задаёт обычную маршрутизацию;
- `DestinationRule` — описывает подмножества `v1` и `v2`, а также ограничения соединений и `outlierDetection`;
- `EnvoyFilter` — работает на исходящем встроенном прокси (sidecar) Pod `istio-client`.

Базовая логика такая:

1. Обычный трафик без специальных заголовков распределяется по канареечной схеме: `90%` в `v1` и `10%` в `v2`.
2. Если запрос приходит с `X-Feature-Enabled: true`, `EnvoyFilter` добавляет внутренний заголовок `x-istio-feature-route: v2`, а `VirtualService` направляет запрос в `v2`.
3. Для тестового маршрута `/fallback-test` реализован отдельный сценарий автоматического переключения (fallback).

### Где находится логика автоматического переключения

Логика автоматического переключения находится в клиентском `EnvoyFilter` для `istio-client`.

Для запроса:

- `GET /fallback-test`
- с заголовком `X-Fallback-Test: true`

Lua-скрипт в `EnvoyFilter` делает следующее:

1. Выполняет внутренний HTTP-вызов строго в подмножество `v1`.
2. Если `v1` отвечает `5xx`, то в рамках того же клиентского запроса выполняет второй внутренний вызов в подмножество `v2`.
3. Возвращает клиенту успешный ответ `v2` вместе с диагностическими заголовками:
   - `X-Fallback-From: v1`
   - `X-Fallback-Reason: upstream-503`

То есть клиент делает один HTTP-запрос к сервису, а повторная попытка и переключение версии происходят внутри прокси.

Это целевой учебный сценарий для отдельного маршрута. В этом решении не заявляется универсальное автоматическое переключение для любых HTTP-методов и маршрутов.

### Как создаётся контролируемая ошибка

Для отдельного маршрута `/fallback-test` версии настроены по-разному:

- `v1` всегда отвечает `503 Service Unavailable` и телом `fallback test forced failure from v1`;
- `v2` отвечает `200 OK` и телом `fallback test served by v2`.

Эта логика включается конфигурацией самого приложения через `FALLBACK_TEST_MODE`, а не имитируется в сценарии оболочки.

### Команды проверки

Проверка выполнялась такими командами:

```bash
go test -count=1 ./booking-service/...
eval "$(minikube -p minikube docker-env)"
docker build -t booking-service:latest ./booking-service
istioctl install --set profile=demo -y
kubectl label namespace default istio-injection=enabled --overwrite
kubectl apply -f kubernetes/service.yaml
helm upgrade --install booking-service-v1 helm/booking-service --namespace default -f values-v1.yaml
helm upgrade --install booking-service-v2 helm/booking-service --namespace default -f values-v2.yaml
kubectl apply -f kubernetes/istio-client.yaml
kubectl apply -f istio/destination-rule.yaml
kubectl apply -f istio/virtual-service.yaml
kubectl apply -f istio/envoy-filter.yaml
kubectl get envoyfilter booking-feature-marker -n default -o jsonpath='{.spec.priority}{"\n"}'
kubectl wait --for=condition=Ready pod/istio-client -n default --timeout=120s
kubectl rollout status deployment/booking-service-v1 -n default --timeout=180s
kubectl rollout status deployment/booking-service-v2 -n default --timeout=180s
./check-istio.sh
./check-canary.sh
./check-feature-flag.sh
./check-fallback.sh
```

### Что подтверждено проверками

#### Istio-инъекция

`check-istio.sh` подтверждает:

- плоскость управления Istio запущена и готова;
- у пространства имён `default` есть метка `istio-injection=enabled`;
- у всех Pod сервиса `booking-service` и у `istio-client` есть `istio-proxy`.

Доказательство: `check-istio-output.txt`.

#### Канареечное распределение 90/10

`check-canary.sh` выполняет 100 запросов и проверяет, что ответы приходят и от `v1`, и от `v2`, а доля `v2` остаётся в разумном диапазоне для схемы `90/10`.

В фактическом прогоне получено `v1=89`, `v2=11`.

Доказательство: `check-canary-output.txt`.

#### Флаг функции

`check-feature-flag.sh` отправляет запрос с `X-Feature-Enabled: true` и проверяет:

- `HTTP 200`;
- `X-Booking-Version: v2`;
- тело `Feature X is enabled!`.

Доказательство: `check-feature-flag-output.txt`.

#### Автоматическое переключение `v1 -> v2`

`check-fallback.sh` делает две проверки.

Первая проверка подтверждает, что источник отказа реален:

- прямой запрос строго в `v1` на `/fallback-test` выполняется с заголовком `X-Direct-Version: v1`;
- ответ: `HTTP 503`;
- в ответе есть `X-Booking-Version: v1`;
- тело: `fallback test forced failure from v1`.

Вторая проверка делает **один** обычный клиентский запрос к тому же адресу:

- `GET /fallback-test`
- с заголовком `X-Fallback-Test: true`

И проверяет, что клиент получает:

- `HTTP 200`;
- `X-Booking-Version: v2`;
- `X-Fallback-From: v1`;
- `X-Fallback-Reason: upstream-503`;
- тело `fallback test served by v2`.

Это и есть подтверждение цепочки:

`v1 вернул 503 -> прокси автоматически выполнил переключение -> клиент получил 200 от v2`.

Доказательство: `check-fallback-output.txt`.

### Итог по требованиям

В текущем решении подтверждены все четыре целевых сценария:

1. обычный трафик без флага функции сохраняет канареечное распределение `90% v1 / 10% v2`;
2. флаг функции `X-Feature-Enabled: true` направляет запрос в `v2`;
3. для контролируемого отказа `v1` реализовано и проверено автоматическое переключение `v1 -> v2` внутри прокси;
4. автоматическое переключение не подменяется удалением Pod, балансировкой или повторным `curl` в shell-скрипте.

### Состав итоговых артефактов

В папке `results/` лежат:

- применённые конфигурации: `values-v1.yaml`, `values-v2.yaml`, `virtual-service.yaml`, `destination-rule.yaml`, `envoy-filter.yaml`;
- журналы проверок: `check-istio-output.txt`, `check-canary-output.txt`, `check-feature-flag-output.txt`, `check-fallback-output.txt`;
- состояние кластера: `kubectl-resources.txt`;
- журнал полного прогона: `test-output.txt`;
- дополнительные данные по Istio: `istio-install-output.txt`, `istio-version.txt`, `pods-istio-system.txt`, `proxy-config-istio-client.txt`, `istio-analyze.txt`.
