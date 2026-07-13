package main

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type fakeStore struct {
	pingErr error
	count   int
}

func (f *fakeStore) Ping(context.Context) error { return f.pingErr }

func (f *fakeStore) Touch(context.Context) (int, error) {
	if f.pingErr != nil {
		return 0, f.pingErr
	}
	f.count++
	return f.count, nil
}

func TestHealthEndpoint(t *testing.T) {
	h := newHandler(&fakeStore{}, nil)
	r := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	w := httptest.NewRecorder()

	h.ServeHTTP(w, r)

	if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"status":"ok"`) {
		t.Fatalf("health response = %d %s", w.Code, w.Body.String())
	}
}

func TestReadyEndpointReflectsDatabaseState(t *testing.T) {
	h := newHandler(&fakeStore{pingErr: errors.New("database unavailable")}, nil)
	r := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	w := httptest.NewRecorder()

	h.ServeHTTP(w, r)

	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("ready status = %d, want %d", w.Code, http.StatusServiceUnavailable)
	}
}

func TestDatabaseEndpointPersistsRequests(t *testing.T) {
	store := &fakeStore{}
	h := newHandler(store, nil)

	for want := 1; want <= 2; want++ {
		r := httptest.NewRequest(http.MethodGet, "/api/db", nil)
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		if w.Code != http.StatusOK || !strings.Contains(w.Body.String(), `"count":`+string(rune('0'+want))) {
			t.Fatalf("db response %d = %d %s", want, w.Code, w.Body.String())
		}
	}
}

func TestMetricsExposeHTTPAndDatabaseCounters(t *testing.T) {
	h := newHandler(&fakeStore{}, nil)
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/api/db", nil))
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/metrics", nil))

	body := w.Body.String()
	for _, metric := range []string{"smoke_http_requests_total", "smoke_db_operations_total 1"} {
		if !strings.Contains(body, metric) {
			t.Fatalf("metrics missing %q:\n%s", metric, body)
		}
	}
}
