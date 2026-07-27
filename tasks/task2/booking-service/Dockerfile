FROM python:3.12-slim

WORKDIR /app

COPY booking-service/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY booking.proto /app/booking.proto
RUN mkdir -p /app/generated && python -m grpc_tools.protoc \
    -I /app \
    --python_out=/app/generated \
    --grpc_python_out=/app/generated \
    /app/booking.proto

COPY booking-service/server.py /app/server.py
COPY booking-service/grpc_client.py /app/grpc_client.py

EXPOSE 9090
CMD ["python", "server.py"]
