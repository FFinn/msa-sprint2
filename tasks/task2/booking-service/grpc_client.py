import argparse
import json
import sys

import grpc

sys.path.insert(0, "/app/generated")
import booking_pb2
import booking_pb2_grpc


def booking_to_dict(booking):
    return {
        "id": booking.id,
        "userId": booking.user_id,
        "hotelId": booking.hotel_id,
        "promoCode": booking.promo_code,
        "discountPercent": booking.discount_percent,
        "price": booking.price,
        "createdAt": booking.created_at,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["list", "create"])
    parser.add_argument("--target", default="localhost:9090")
    parser.add_argument("--user-id", default="")
    parser.add_argument("--hotel-id", default="")
    parser.add_argument("--promo-code", default="")
    args = parser.parse_args()

    channel = grpc.insecure_channel(args.target)
    client = booking_pb2_grpc.BookingServiceStub(channel)

    try:
        if args.command == "list":
            response = client.ListBookings(
                booking_pb2.BookingListRequest(user_id=args.user_id)
            )
            print(json.dumps([booking_to_dict(item) for item in response.bookings], indent=2))
            return

        response = client.CreateBooking(
            booking_pb2.BookingRequest(
                user_id=args.user_id,
                hotel_id=args.hotel_id,
                promo_code=args.promo_code,
            )
        )
        print(json.dumps(booking_to_dict(response), indent=2))
    except grpc.RpcError as exc:
        print(f"{exc.code().name}: {exc.details()}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
