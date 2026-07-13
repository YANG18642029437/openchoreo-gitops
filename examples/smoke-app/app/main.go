package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync/atomic"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type store interface {
	Ping(context.Context) error
	Touch(context.Context) (int, error)
}

type postgresStore struct{ db *sql.DB }

func (p *postgresStore) Ping(ctx context.Context) error { return p.db.PingContext(ctx) }

func (p *postgresStore) Touch(ctx context.Context) (int, error) {
	if _, err := p.db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS smoke_requests (
		id bigserial PRIMARY KEY,
		created_at timestamptz NOT NULL DEFAULT now()
	)`); err != nil {
		return 0, err
	}
	if _, err := p.db.ExecContext(ctx, `INSERT INTO smoke_requests DEFAULT VALUES`); err != nil {
		return 0, err
	}
	var count int
	err := p.db.QueryRowContext(ctx, `SELECT count(*) FROM smoke_requests`).Scan(&count)
	return count, err
}

type traceExporter struct {
	endpoint string
	client   *http.Client
}

func (t *traceExporter) export(ctx context.Context, name string, failed bool, started time.Time) {
	if t == nil || t.endpoint == "" {
		return
	}
	traceID, spanID := randomHex(16), randomHex(8)
	status := 1
	if failed {
		status = 2
	}
	payload := map[string]any{"resourceSpans": []any{map[string]any{
		"resource": map[string]any{"attributes": []any{
			map[string]any{"key": "service.name", "value": map[string]any{"stringValue": "phase05-smoke"}},
			map[string]any{"key": "deployment.environment", "value": map[string]any{"stringValue": os.Getenv("OPENCHOREO_ENVIRONMENT")}},
		}},
		"scopeSpans": []any{map[string]any{"scope": map[string]any{"name": "phase05-smoke"}, "spans": []any{map[string]any{
			"traceId": traceID, "spanId": spanID, "name": name, "kind": 2,
			"startTimeUnixNano": fmt.Sprint(started.UnixNano()), "endTimeUnixNano": fmt.Sprint(time.Now().UnixNano()),
			"status": map[string]any{"code": status},
		}}}},
	}}}
	body, err := json.Marshal(payload)
	if err != nil {
		return
	}
	url := strings.TrimRight(t.endpoint, "/") + "/v1/traces"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := t.client.Do(req)
	if err == nil {
		resp.Body.Close()
	}
}

func randomHex(size int) string {
	b := make([]byte, size)
	if _, err := rand.Read(b); err != nil {
		return strings.Repeat("0", size*2)
	}
	return hex.EncodeToString(b)
}

type appHandler struct {
	store       store
	traces      *traceExporter
	httpTotal   atomic.Uint64
	dbTotal     atomic.Uint64
	dbFailures  atomic.Uint64
}

func newHandler(s store, traces *traceExporter) http.Handler {
	a := &appHandler{store: s, traces: traces}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", a.health)
	mux.HandleFunc("/readyz", a.ready)
	mux.HandleFunc("/api/db", a.database)
	mux.HandleFunc("/metrics", a.metrics)
	return a.instrument(mux)
}

func (a *appHandler) instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		a.httpTotal.Add(1)
		next.ServeHTTP(w, r)
		log.Printf(`{"level":"info","method":%q,"path":%q,"duration_ms":%d}`, r.Method, r.URL.Path, time.Since(started).Milliseconds())
		go a.traces.export(context.Background(), r.Method+" "+r.URL.Path, false, started)
	})
}

func (a *appHandler) health(w http.ResponseWriter, _ *http.Request) { writeJSON(w, http.StatusOK, map[string]any{"status": "ok"}) }

func (a *appHandler) ready(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := a.store.Ping(ctx); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"status": "not-ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ready"})
}

func (a *appHandler) database(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 5*time.Second)
	defer cancel()
	count, err := a.store.Touch(ctx)
	if err != nil {
		a.dbFailures.Add(1)
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "database unavailable"})
		return
	}
	a.dbTotal.Add(1)
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "count": count})
}

func (a *appHandler) metrics(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "# TYPE smoke_http_requests_total counter\nsmoke_http_requests_total %d\n", a.httpTotal.Load())
	fmt.Fprintf(w, "# TYPE smoke_db_operations_total counter\nsmoke_db_operations_total %d\n", a.dbTotal.Load())
	fmt.Fprintf(w, "# TYPE smoke_db_failures_total counter\nsmoke_db_failures_total %d\n", a.dbFailures.Load())
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	exporter := &traceExporter{endpoint: os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"), client: &http.Client{Timeout: 3 * time.Second}}
	server := &http.Server{Addr: ":" + port, Handler: newHandler(&postgresStore{db: db}, exporter), ReadHeaderTimeout: 5 * time.Second}
	log.Printf(`{"level":"info","message":"phase05 smoke app listening","port":%q}`, port)
	log.Fatal(server.ListenAndServe())
}
