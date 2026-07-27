package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPing(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/ping", nil)
	response := httptest.NewRecorder()

	newRouter(false).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "pong" {
		t.Fatalf("expected body %q, got %q", "pong", response.Body.String())
	}
}

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()

	newRouter(false).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "ok" {
		t.Fatalf("expected body %q, got %q", "ok", response.Body.String())
	}
}

func TestReady(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/ready", nil)
	response := httptest.NewRecorder()

	newRouter(false).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "ready" {
		t.Fatalf("expected body %q, got %q", "ready", response.Body.String())
	}
}

func TestFeatureDisabledReturnsNotFound(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/feature", nil)
	response := httptest.NewRecorder()

	newRouter(false).ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", response.Code)
	}
}

func TestFeatureEnabledReturnsBody(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/feature", nil)
	response := httptest.NewRecorder()

	newRouter(true).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "Feature X is enabled!" {
		t.Fatalf("expected body %q, got %q", "Feature X is enabled!", response.Body.String())
	}
}
