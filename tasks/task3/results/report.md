# Отчёт по заданию 3

## Реализованные интеграции

- `booking-subgraph` получает список бронирований через реальный gRPC-вызов
  `BookingService.ListBookings` в `booking-service` из задания 2.
- Поле `Booking.hotel` разрешается через федеративную ссылку `Hotel(id)` в `hotel-subgraph`.
- `hotel-subgraph` получает карточку отеля через реальный REST-вызов в монолит:
  `GET /api/hotels/{id}`.
- `apollo-gateway` пробрасывает HTTP-заголовок `userid` в подграфы.
- На `GET /` шлюз отдаёт локальный GraphQL Playground для проверки через интерфейс.
  GraphQL POST-запросы продолжают обслуживаться тем же `http://localhost:4000/`.

## ACL

- Резолвер `bookingsByUser(userId)` возвращает данные только если заголовок `userid`
  совпадает с аргументом `userId`.
- При несовпадении возвращается строго пустой список `[]`, без GraphQL errors.

## Подготовка данных

- `booking-db-init/001-bookings.sql` создаёт в `booking-db` тестовое бронирование
  `user1 -> h1` с числовым BIGINT `id = 1`.
- `collect-results.sh` применяет `monolith-fixtures.sql` после старта монолита и
  создаёт отель `h1`.
- В REST-ответе монолита нет отдельного поля `name`, поэтому в `hotel-subgraph`
  GraphQL-поле `Hotel.name` формируется из `description`. Для тестовой записи `h1`
  в `description` записано значение `Hotel One`.

## Артефакты

- `docker-ps.txt` — состояние контейнеров;
- `test-log.txt` — полный лог реальной проверки;
- `graphql-allowed.json` — успешный запрос;
- `graphql-denied.json` — запрос, отклонённый проверкой доступа;
- `graphql-allowed.png` — реальный снимок интерфейса с разрешённым запросом в GraphQL Playground;
- `graphql-denied.png` — реальный снимок интерфейса с отклонением по ACL в GraphQL Playground;
- `compose.log` — логи `apollo-gateway`, `booking-subgraph`, `hotel-subgraph`.
