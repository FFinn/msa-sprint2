package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestPing(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/ping", nil)
	response := httptest.NewRecorder()

	newRouter(false, "v1", "").ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "pong" {
		t.Fatalf("expected body %q, got %q", "pong", response.Body.String())
	}
	if got := response.Header().Get("X-Booking-Version"); got != "v1" {
		t.Fatalf("expected X-Booking-Version %q, got %q", "v1", got)
	}
}

func TestHealth(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()

	newRouter(false, "v1", "").ServeHTTP(response, request)

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

	newRouter(false, "v1", "").ServeHTTP(response, request)

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

	newRouter(false, "v1", "").ServeHTTP(response, request)

	if response.Code != http.StatusNotFound {
		t.Fatalf("expected status 404, got %d", response.Code)
	}
}

func TestFeatureEnabledReturnsBody(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/feature", nil)
	response := httptest.NewRecorder()

	newRouter(true, "v2", "").ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "Feature X is enabled!" {
		t.Fatalf("expected body %q, got %q", "Feature X is enabled!", response.Body.String())
	}
}

func TestFallbackTestFailureModeReturns503(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/fallback-test", nil)
	response := httptest.NewRecorder()

	newRouter(false, "v1", "fail").ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status 503, got %d", response.Code)
	}
	if response.Body.String() != "fallback test forced failure from v1" {
		t.Fatalf("expected failure body, got %q", response.Body.String())
	}
	if got := response.Header().Get("X-Booking-Version"); got != "v1" {
		t.Fatalf("expected X-Booking-Version %q, got %q", "v1", got)
	}
}

func TestFallbackTestSuccessModeReturns200(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/fallback-test", nil)
	response := httptest.NewRecorder()

	newRouter(false, "v2", "success").ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	if response.Body.String() != "fallback test served by v2" {
		t.Fatalf("expected success body, got %q", response.Body.String())
	}
	if got := response.Header().Get("X-Booking-Version"); got != "v2" {
		t.Fatalf("expected X-Booking-Version %q, got %q", "v2", got)
	}
}
