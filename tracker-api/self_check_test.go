package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestTrackerAPI(t *testing.T) {
	// Test OPTIONS pre-flight request CORS response
	t.Run("OPTIONS_Preflight", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodOptions, "/api/tracker", nil)
		w := httptest.NewRecorder()
		trackerHandler(w, req)

		res := w.Result()
		if res.StatusCode != http.StatusOK {
			t.Errorf("expected status 200 OK, got %d", res.StatusCode)
		}
		if origin := res.Header.Get("Access-Control-Allow-Origin"); origin != "*" {
			t.Errorf("expected Access-Control-Allow-Origin: *, got %s", origin)
		}
	})

	// Test GET request headers and JSON response payload
	t.Run("GET_Request", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/tracker", nil)
		w := httptest.NewRecorder()
		trackerHandler(w, req)

		res := w.Result()
		if res.StatusCode != http.StatusOK {
			t.Errorf("expected status 200 OK, got %d", res.StatusCode)
		}
		if origin := res.Header.Get("Access-Control-Allow-Origin"); origin != "*" {
			t.Errorf("expected Access-Control-Allow-Origin: *, got %s", origin)
		}
		if cc := res.Header.Get("Cache-Control"); cc != "no-store, no-cache, must-revalidate, max-age=0" {
			t.Errorf("expected Cache-Control header to be frozen, got %s", cc)
		}
		if ct := res.Header.Get("Content-Type"); ct != "application/json" {
			t.Errorf("expected Content-Type: application/json, got %s", ct)
		}

		var payload ResponsePayload
		if err := json.NewDecoder(res.Body).Decode(&payload); err != nil {
			t.Fatalf("failed to decode JSON: %v", err)
		}
		if payload.ActiveNow != 3 || payload.TotalViews != 99 || payload.Status != "Healthy" {
			t.Errorf("incorrect mock response values: %+v", payload)
		}
	})
}
