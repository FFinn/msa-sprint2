FROM --platform=$BUILDPLATFORM golang:1.22-alpine AS build

WORKDIR /src
ARG TARGETOS
ARG TARGETARCH
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -trimpath -ldflags="-s -w" -o /out/booking-service .

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/booking-service /booking-service
EXPOSE 8080
ENTRYPOINT ["/booking-service"]
