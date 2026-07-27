package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	serviceVersion := os.Getenv("SERVICE_VERSION")
	if serviceVersion == "" {
		serviceVersion = "unknown"
	}

	router := newRouter(
		os.Getenv("ENABLE_FEATURE_X") == "true",
		serviceVersion,
		os.Getenv("FALLBACK_TEST_MODE"),
	)

	log.Println("Сервис бронирований запущен на :8080")
	log.Fatal(http.ListenAndServe(":8080", router))
}

func newRouter(enableFeatureX bool, serviceVersion, fallbackTestMode string) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("pong"))
	})
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ready"))
	})
	mux.HandleFunc("/fallback-test", func(w http.ResponseWriter, r *http.Request) {
		if fallbackTestMode == "fail" {
			w.WriteHeader(http.StatusServiceUnavailable)
			_, _ = w.Write([]byte("fallback test forced failure from " + serviceVersion))
			return
		}

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("fallback test served by " + serviceVersion))
	})

	if enableFeatureX {
		mux.HandleFunc("/feature", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("Feature X is enabled!"))
		})
	}

	return withServiceVersion(mux, serviceVersion)
}

func withServiceVersion(next http.Handler, serviceVersion string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Booking-Version", serviceVersion)
		next.ServeHTTP(w, r)
	})
}
