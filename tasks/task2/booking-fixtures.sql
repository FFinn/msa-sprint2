TRUNCATE TABLE booking_outbox, bookings RESTART IDENTITY CASCADE;

INSERT INTO bookings (
    id,
    user_id,
    hotel_id,
    promo_code,
    discount_percent,
    price,
    created_at
)
VALUES
    (1, 'test-user-2', 'test-hotel-1', 'TESTCODE1', 10.0, 90.0, '2026-01-01T10:00:00Z'),
    (2, 'test-user-3', 'test-hotel-1', NULL, 0.0, 80.0, '2026-01-02T10:00:00Z');

SELECT setval(
    pg_get_serial_sequence('bookings', 'id'),
    COALESCE((SELECT MAX(id) FROM bookings), 1),
    true
);
