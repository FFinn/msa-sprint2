import json
import logging
import os
import signal
import time
from typing import Any

import psycopg
from confluent_kafka import Consumer, KafkaException


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("booking-history-service")


DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://hotelio:hotelio@booking-history-db:5432/booking_history",
)
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
BOOKING_CREATED_TOPIC = os.getenv("BOOKING_CREATED_TOPIC", "booking-created")
CONSUMER_GROUP_ID = os.getenv("CONSUMER_GROUP_ID", "booking-history-service")
DB_WAIT_ATTEMPTS = int(os.getenv("DB_WAIT_ATTEMPTS", "60"))
DB_WAIT_SECONDS = float(os.getenv("DB_WAIT_SECONDS", "2"))
KAFKA_RETRY_SECONDS = float(os.getenv("KAFKA_RETRY_SECONDS", "3"))


def wait_for_postgres() -> None:
    for attempt in range(1, DB_WAIT_ATTEMPTS + 1):
        try:
            with psycopg.connect(DATABASE_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
            log.info("booking-history-db is reachable")
            return
        except psycopg.OperationalError:
            log.info(
                "Waiting for booking-history-db (%s/%s)",
                attempt,
                DB_WAIT_ATTEMPTS,
            )
            time.sleep(DB_WAIT_SECONDS)
    raise RuntimeError("booking-history-db did not become reachable")


def init_schema() -> None:
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS booking_history (
                    booking_id BIGINT PRIMARY KEY,
                    user_id VARCHAR(255) NOT NULL,
                    hotel_id VARCHAR(255) NOT NULL,
                    promo_code VARCHAR(255),
                    discount_percent DOUBLE PRECISION NOT NULL,
                    price DOUBLE PRECISION NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL,
                    received_at TIMESTAMPTZ NOT NULL DEFAULT now()
                );

                CREATE INDEX IF NOT EXISTS booking_history_user_id_idx
                    ON booking_history(user_id);
                CREATE INDEX IF NOT EXISTS booking_history_hotel_id_idx
                    ON booking_history(hotel_id);
                CREATE INDEX IF NOT EXISTS booking_history_created_at_idx
                    ON booking_history(created_at);
                """
            )
        conn.commit()
    log.info("booking-history-db schema is ready")


def save_event(event: dict[str, Any]) -> None:
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO booking_history (
                    booking_id,
                    user_id,
                    hotel_id,
                    promo_code,
                    discount_percent,
                    price,
                    created_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (booking_id) DO NOTHING
                """,
                (
                    int(event["bookingId"]),
                    event["userId"],
                    event["hotelId"],
                    event.get("promoCode"),
                    float(event["discountPercent"]),
                    float(event["price"]),
                    event["createdAt"],
                ),
            )
        conn.commit()


def build_consumer() -> Consumer:
    consumer = Consumer(
        {
            "bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
            "group.id": CONSUMER_GROUP_ID,
            "auto.offset.reset": "earliest",
            "enable.auto.commit": False,
        }
    )
    consumer.subscribe([BOOKING_CREATED_TOPIC])
    return consumer


def consume_forever() -> None:
    wait_for_postgres()
    init_schema()

    stop_event = {"stop": False}

    def request_stop(*_args: Any) -> None:
        log.info("Stopping booking-history-service")
        stop_event["stop"] = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    consumer: Consumer | None = None
    while not stop_event["stop"]:
        try:
            if consumer is None:
                consumer = build_consumer()
                log.info(
                    "Connected to Kafka topic %s with group %s",
                    BOOKING_CREATED_TOPIC,
                    CONSUMER_GROUP_ID,
                )

            message = consumer.poll(1.0)
            if message is None:
                continue
            if message.error():
                raise KafkaException(message.error())

            payload = json.loads(message.value().decode("utf-8"))
            save_event(payload)
            consumer.commit(message=message, asynchronous=False)
            log.info(
                "Saved booking history record for booking_id=%s",
                payload["bookingId"],
            )
        except Exception:
            log.exception("Kafka consume loop failed")
            if consumer is not None:
                try:
                    consumer.close()
                except Exception:
                    log.warning("Failed to close Kafka consumer cleanly", exc_info=True)
            consumer = None
            if not stop_event["stop"]:
                time.sleep(KAFKA_RETRY_SECONDS)

    if consumer is not None:
        consumer.close()


if __name__ == "__main__":
    consume_forever()
