# Задание 3

## Что реализовано

- `apollo-gateway` объединяет `booking-subgraph` и `hotel-subgraph` через Apollo Federation;
- `booking-subgraph` получает реальные данные по gRPC из `booking-service` задания 2;
- `hotel-subgraph` получает реальные данные по REST из монолита через `GET /api/hotels/{id}`;
- ACL на `bookingsByUser(userId)` реализован в `booking-subgraph`: если заголовок `userid`
  отсутствует или не совпадает с аргументом `userId`, возвращается пустой список `[]`.

## Подготовка данных

- В `booking-db` используется набор тестовых данных из `booking-db-init/001-bookings.sql`.
  Он создаёт совместимую с заданием 2 таблицу `bookings` и добавляет запись
  `user1 -> h1` с числовым BIGINT `id = 1`.
- Для монолита отдельный набор тестовых данных по отелю загружается после старта приложения командой
  из `collect-results.sh`. Скрипт применяет [monolith-fixtures.sql](monolith-fixtures.sql),
  создавая отель `h1` в таблице `hotel`.
- REST API монолита не возвращает отдельное поле `name`, а передаёт `description`.
  Поэтому в `hotel-subgraph` поле GraphQL `hotel.name` формируется из `description`.
  Для тестовой записи `h1` в `description` хранится значение `Hotel One`.

## Архитектурный путь

Клиентский запрос идёт по цепочке:

`клиент -> apollo-gateway -> booking-subgraph -> gRPC booking-service`

и далее поле `Booking.hotel` разрешается через федерацию:

`booking-subgraph -> hotel-subgraph -> REST API монолита /api/hotels/{id}`

## Запуск

Остановите другие задания, если они заняли порты `4000`, `8084` или `9090`, затем выполните:

```bash
cd tasks/task3
docker compose down --volumes --remove-orphans
docker compose up -d --build
./collect-results.sh
```

## Проверочный запрос

```graphql
query {
  bookingsByUser(userId: "user1") {
    id
    hotel {
      name
      city
    }
    discountPercent
  }
}
```

Перед запросом нужно передать заголовок `userid: user1`.
