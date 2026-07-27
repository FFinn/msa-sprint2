import json
import logging
import os
import signal
import sys
import threading
import time
import uuid
from concurrent import futures
from datetime import datetime, timezone
from typing import Any

import grpc
import psycopg
import requests
from confluent_kafka import Producer
from psycopg.rows import dict_row

sys.path.insert(0, "/app/generated")
import booking_pb2
import booking_pb2_grpc


logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("booking-service")


DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://hotelio:hotelio@booking-db:5432/bookings"
)
MONOLITH_BASE_URL = os.getenv("MONOLITH_BASE_URL", "http://monolith:8080").rstrip("/")
KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "kafka:9092")
BOOKING_CREATED_TOPIC = os.getenv("BOOKING_CREATED_TOPIC", "booking-created")
GRPC_PORT = int(os.getenv("GRPC_PORT", "9090"))
DB_WAIT_ATTEMPTS = int(os.getenv("DB_WAIT_ATTEMPTS", "60"))
DB_WAIT_SECONDS = float(os.getenv("DB_WAIT_SECONDS", "2"))
OUTBOX_POLL_SECONDS = float(os.getenv("OUTBOX_POLL_SECONDS", "1"))


class ValidationError(Exception):
    def __init__(self, status_code: grpc.StatusCode, message: str):
        super().__init__(message)
        self.status_code = status_code
        self.message = message


class DependencyUnavailableError(Exception):
    pass


class BookingOutboxPublisher:
    def __init__(self, stop_event: threading.Event):
        self.stop_event = stop_event
        self.producer: Producer | None = None

    def ensure_producer(self) -> Producer:
        if self.producer is None:
            self.producer = Producer(
                {
                    "bootstrap.servers": KAFKA_BOOTSTRAP_SERVERS,
                    "acks": "all",
                }
            )
        return self.producer

    def fetch_pending_events(self) -> list[dict[str, Any]]:
        with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT event_id, payload
                    FROM booking_outbox
                    WHERE published_at IS NULL
                    ORDER BY created_at, booking_id
                    LIMIT 100
                    """
                )
                return cur.fetchall()

    def mark_published(self, event_id: str) -> None:
        with psycopg.connect(DATABASE_URL) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    UPDATE booking_outbox
                    SET published_at = now()
                    WHERE event_id = %s
                    """,
                    (event_id,),
                )
            conn.commit()

    def publish_once(self) -> None:
        events = self.fetch_pending_events()
        if not events:
            return

        producer = self.ensure_producer()
        for event in events:
            payload = event["payload"]
            event_id = str(event["event_id"])
            delivery_state: dict[str, Any] = {"error": None, "delivered": False}

            def on_delivery(err, msg) -> None:
                if err is not None:
                    delivery_state["error"] = err
                    return
                delivery_state["delivered"] = True

            producer.produce(
                BOOKING_CREATED_TOPIC,
                key=event_id.encode("utf-8"),
                value=json.dumps(payload).encode("utf-8"),
                on_delivery=on_delivery,
            )
            pending_messages = producer.flush(10)
            if delivery_state["error"] is not None:
                raise RuntimeError(
                    f"Kafka delivery failed for event_id={event_id}: {delivery_state['error']}"
                )
            if pending_messages != 0 or not delivery_state["delivered"]:
                raise RuntimeError(
                    f"Kafka delivery was not confirmed for event_id={event_id}"
                )
            self.mark_published(event_id)
            log.info(
                "Published BookingCreated event_id=%s booking_id=%s",
                event_id,
                payload["bookingId"],
            )
        producer.flush()

    def run(self) -> None:
        while not self.stop_event.is_set():
            try:
                self.publish_once()
            except Exception:
                log.exception("Outbox publish attempt failed")
                if self.producer is not None:
                    try:
                        self.producer.flush(5)
                    except Exception:
                        log.warning("Failed to close Kafka producer cleanly", exc_info=True)
                    self.producer = None
            self.stop_event.wait(OUTBOX_POLL_SECONDS)

        if self.producer is not None:
            try:
                self.producer.flush(5)
            except Exception:
                log.warning("Failed to close Kafka producer cleanly", exc_info=True)


def wait_for_postgres() -> None:
    for attempt in range(1, DB_WAIT_ATTEMPTS + 1):
        try:
            with psycopg.connect(DATABASE_URL) as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT 1")
            log.info("booking-db is reachable")
            return
        except psycopg.OperationalError:
            log.info("Waiting for booking-db (%s/%s)", attempt, DB_WAIT_ATTEMPTS)
            time.sleep(DB_WAIT_SECONDS)
    raise RuntimeError("booking-db did not become reachable")


def init_schema() -> None:
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS bookings (
                    id BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
                    user_id VARCHAR(255) NOT NULL,
                    hotel_id VARCHAR(255) NOT NULL,
                    promo_code VARCHAR(255),
                    discount_percent DOUBLE PRECISION NOT NULL,
                    price DOUBLE PRECISION NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                );

                CREATE INDEX IF NOT EXISTS bookings_user_id_idx ON bookings(user_id);
                CREATE INDEX IF NOT EXISTS bookings_created_at_idx ON bookings(created_at);

                CREATE TABLE IF NOT EXISTS booking_outbox (
                    event_id UUID PRIMARY KEY,
                    booking_id BIGINT NOT NULL UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
                    payload JSONB NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
                    published_at TIMESTAMPTZ
                );

                CREATE INDEX IF NOT EXISTS booking_outbox_pending_idx
                    ON booking_outbox (published_at, created_at);
                """
            )
        conn.commit()
    log.info("booking-db schema is ready")


def isoformat_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def require_non_blank(field_name: str, value: str) -> str:
    if value is None or not value.strip():
        raise ValidationError(
            grpc.StatusCode.INVALID_ARGUMENT,
            f"{field_name} must not be blank",
        )
    return value.strip()


def rest_call(path: str, method: str = "GET") -> tuple[int, str]:
    url = f"{MONOLITH_BASE_URL}{path}"
    try:
        response = requests.request(method=method, url=url, timeout=5)
        return response.status_code, response.text
    except requests.RequestException as exc:
        raise DependencyUnavailableError(f"Failed to call monolith endpoint {path}") from exc


def rest_bool(path: str) -> bool:
    status_code, body = rest_call(path)
    if status_code != 200:
        raise DependencyUnavailableError(f"Unexpected HTTP {status_code} from {path}")
    return body.strip().lower() == "true"


def rest_status(path: str) -> str:
    status_code, body = rest_call(path)
    if status_code != 200:
        raise DependencyUnavailableError(f"Unexpected HTTP {status_code} from {path}")
    return body.strip().strip('"')


def resolve_discount(user_id: str, promo_code: str) -> float:
    if not promo_code:
        return 0.0

    status_code, body = rest_call(
        f"/api/promos/validate?code={promo_code}&userId={user_id}",
        method="POST",
    )
    if status_code == 200:
        payload = json.loads(body)
        return float(payload.get("discount", 0.0))
    if status_code == 400:
        log.info(
            "Promo code %s is not applicable for user %s; booking continues without discount",
            promo_code,
            user_id,
        )
        return 0.0
    raise DependencyUnavailableError(
        f"Unexpected HTTP {status_code} from /api/promos/validate"
    )


def resolve_base_price(user_id: str) -> float:
    user_status = rest_status(f"/api/users/{user_id}/status")
    return 80.0 if user_status.upper() == "VIP" else 100.0


def validate_business_rules(user_id: str, hotel_id: str) -> None:
    if not rest_bool(f"/api/users/{user_id}/active"):
        raise ValidationError(grpc.StatusCode.FAILED_PRECONDITION, "User is inactive")
    if rest_bool(f"/api/users/{user_id}/blacklisted"):
        raise ValidationError(grpc.StatusCode.FAILED_PRECONDITION, "User is blacklisted")
    if not rest_bool(f"/api/hotels/{hotel_id}/operational"):
        raise ValidationError(
            grpc.StatusCode.FAILED_PRECONDITION,
            "Hotel is not operational",
        )
    if not rest_bool(f"/api/reviews/hotel/{hotel_id}/trusted"):
        raise ValidationError(
            grpc.StatusCode.FAILED_PRECONDITION,
            "Hotel is not trusted based on reviews",
        )
    if rest_bool(f"/api/hotels/{hotel_id}/fully-booked"):
        raise ValidationError(grpc.StatusCode.FAILED_PRECONDITION, "Hotel is fully booked")


def create_booking_record(user_id: str, hotel_id: str, promo_code: str) -> dict[str, Any]:
    validate_business_rules(user_id, hotel_id)
    base_price = resolve_base_price(user_id)
    discount_percent = resolve_discount(user_id, promo_code)
    price = base_price - discount_percent
    created_at = datetime.now(timezone.utc)
    event_id = uuid.uuid4()

    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO bookings (user_id, hotel_id, promo_code, discount_percent, price, created_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id, user_id, hotel_id, promo_code, discount_percent, price, created_at
                """,
                (
                    user_id,
                    hotel_id,
                    promo_code or None,
                    discount_percent,
                    price,
                    created_at,
                ),
            )
            booking = cur.fetchone()

            payload = {
                "eventId": str(event_id),
                "eventType": "BookingCreated",
                "bookingId": booking["id"],
                "userId": booking["user_id"],
                "hotelId": booking["hotel_id"],
                "promoCode": booking["promo_code"],
                "discountPercent": booking["discount_percent"],
                "price": booking["price"],
                "createdAt": isoformat_utc(booking["created_at"]),
            }

            cur.execute(
                """
                INSERT INTO booking_outbox (event_id, booking_id, payload)
                VALUES (%s, %s, %s::jsonb)
                """,
                (event_id, booking["id"], json.dumps(payload)),
            )
        conn.commit()

    return booking


def fetch_bookings(user_id: str | None) -> list[dict[str, Any]]:
    query = """
        SELECT id, user_id, hotel_id, promo_code, discount_percent, price, created_at
        FROM bookings
    """
    params: tuple[Any, ...] = ()
    if user_id:
        query += " WHERE user_id = %s"
        params = (user_id,)
    query += " ORDER BY id"

    with psycopg.connect(DATABASE_URL, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query, params)
            return cur.fetchall()


def to_proto(row: dict[str, Any]) -> booking_pb2.BookingResponse:
    return booking_pb2.BookingResponse(
        id=str(row["id"]),
        user_id=row["user_id"],
        hotel_id=row["hotel_id"],
        promo_code=row["promo_code"] or "",
        discount_percent=float(row["discount_percent"]),
        price=float(row["price"]),
        created_at=isoformat_utc(row["created_at"]),
    )


class BookingService(booking_pb2_grpc.BookingServiceServicer):
    def CreateBooking(self, request, context):
        try:
            user_id = require_non_blank("user_id", request.user_id)
            hotel_id = require_non_blank("hotel_id", request.hotel_id)
            promo_code = (request.promo_code or "").strip()
            booking = create_booking_record(user_id, hotel_id, promo_code)
            return to_proto(booking)
        except ValidationError as exc:
            context.abort(exc.status_code, exc.message)
        except DependencyUnavailableError:
            log.exception("Dependency failure during CreateBooking")
            context.abort(
                grpc.StatusCode.UNAVAILABLE,
                "Booking service temporarily unavailable",
            )
        except Exception:
            log.exception("Internal failure during CreateBooking")
            context.abort(grpc.StatusCode.INTERNAL, "Internal booking service error")

    def ListBookings(self, request, context):
        try:
            user_id = (request.user_id or "").strip()
            rows = fetch_bookings(user_id if user_id else None)
            return booking_pb2.BookingListResponse(
                bookings=[to_proto(row) for row in rows]
            )
        except Exception:
            log.exception("Internal failure during ListBookings")
            context.abort(grpc.StatusCode.INTERNAL, "Internal booking service error")


def serve() -> None:
    wait_for_postgres()
    init_schema()

    stop_event = threading.Event()
    publisher = BookingOutboxPublisher(stop_event)
    publisher_thread = threading.Thread(target=publisher.run, daemon=True)
    publisher_thread.start()

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=16))
    booking_pb2_grpc.add_BookingServiceServicer_to_server(BookingService(), server)
    server.add_insecure_port(f"[::]:{GRPC_PORT}")
    server.start()
    log.info("booking-service gRPC server started on port %s", GRPC_PORT)

    def shutdown(*_args: Any) -> None:
        log.info("Shutting down booking-service")
        stop_event.set()
        server.stop(grace=5)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        server.wait_for_termination()
    finally:
        stop_event.set()
        publisher_thread.join(timeout=5)


if __name__ == "__main__":
    serve()
