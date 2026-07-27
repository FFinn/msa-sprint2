DELETE FROM hotel WHERE id = 'h1';

INSERT INTO hotel (id, operational, fully_booked, city, rating, description)
VALUES ('h1', true, false, 'Moscow', 4.9, 'Hotel One');
