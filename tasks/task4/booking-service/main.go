package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	router := newRouter(os.Getenv("ENABLE_FEATURE_X") == "true")

	log.Println("Сервис бронирований запущен на :8080")
	log.Fatal(http.ListenAndServe(":8080", router))
}

func newRouter(enableFeatureX bool) http.Handler {
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

	if enableFeatureX {
		mux.HandleFunc("/feature", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("Feature X is enabled!"))
		})
	}

	return mux
}
