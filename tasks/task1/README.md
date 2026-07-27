# Задание 1

Артефакты задания:

- ADR: [results/ADR/001-booking-service-extraction.md](results/ADR/001-booking-service-extraction.md)
- Контекстная диаграмма C4 (C1): [results/ADR/diagram/context.puml](results/ADR/diagram/context.puml)
- Целевая контейнерная диаграмма C4 (C2): [results/ADR/diagram/task1-to-be.puml](results/ADR/diagram/task1-to-be.puml)
- Лог реального запуска: [results/test-log.txt](results/test-log.txt)
- Скрипт проверки: [verify.sh](verify.sh)
- Регрессионные HTTP-проверки: [../../test/readme.md](../../test/readme.md)

## Подготовка окружения

1. Установите Docker и Docker Compose.
2. Создайте внешнюю сеть, которую используют `task1` и следующие задачи:

```bash
docker network create hotelio-net 2>/dev/null || true
```

3. Если нужно пересобрать JAR монолита для Docker-образа:

```bash
cd ../../hotelio-monolith
bash ./gradlew build
```

## Запуск задания

```bash
cd tasks/task1
docker compose up -d --build
```

Полный воспроизводимый прогон:

```bash
cd tasks/task1
./verify.sh
```

Фактические REST-контракты монолита для бронирований:

- список бронирований: `GET http://localhost:8084/api/bookings`
- список бронирований пользователя: `GET http://localhost:8084/api/bookings?userId=test-user-2`
- создание бронирования: `POST http://localhost:8084/api/bookings?userId=test-user-3&hotelId=test-hotel-1`
- создание с промокодом: `POST http://localhost:8084/api/bookings?userId=test-user-2&hotelId=test-hotel-1&promoCode=TESTCODE1`

Для регрессионных HTTP-тестов используются реальные фикстуры из [../../test/init-fixtures.sql](../../test/init-fixtures.sql) и сценарий из [../../test/readme.md](../../test/readme.md).

Практический запуск регрессионного контейнера для `task1` лучше выполнять внутри `hotelio-net`, чтобы он обращался к сервисам по именам контейнеров:

```bash
cd tasks/task1
docker build -t hotelio-tester ../../test
docker run --rm \
  --network hotelio-net \
  -e DB_HOST=hotelio-db \
  -e DB_PORT=5432 \
  -e DB_NAME=hotelio \
  -e DB_USER=hotelio \
  -e DB_PASSWORD=hotelio \
  -e API_URL=http://hotelio-monolith:8080 \
  hotelio-tester
```

Негативные сценарии бронирования считаются штатными бизнес-ошибками и возвращают `409 Conflict` с JSON-ответом без stack trace в логах приложения.
