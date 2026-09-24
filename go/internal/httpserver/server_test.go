package httpserver

import (
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"testing/fstest"

	"github.com/titaniumcoder/planning-poker/go/internal/config"
)

func TestHealthAndSecurityHeaders(t *testing.T) {
	server := testServer(t)
	request := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	response := httptest.NewRecorder()

	server.HTTP.Handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if response.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatal("security headers missing")
	}
	if response.Header().Get("X-Request-ID") == "" {
		t.Fatal("request id missing")
	}
}

func TestReadinessEndpoint(t *testing.T) {
	server := testServer(t)
	response := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if response.Code != http.StatusOK || response.Body.String() != "ready" {
		t.Fatalf("response = %d %q", response.Code, response.Body.String())
	}
}

func TestSPAFallbackAndMissingAPI(t *testing.T) {
	server := testServer(t)

	spa := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(spa, httptest.NewRequest(http.MethodGet, "/poker/example", nil))
	if spa.Code != http.StatusOK || spa.Body.String() != "<main>app</main>" {
		t.Fatalf("SPA response = %d %q", spa.Code, spa.Body.String())
	}

	api := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(api, httptest.NewRequest(http.MethodGet, "/api/missing", nil))
	if api.Code != http.StatusNotFound {
		t.Fatalf("API status = %d", api.Code)
	}
}

func TestSPAAssetsHaveContentTypesAndImmutableCaching(t *testing.T) {
	server := testServer(t)
	response := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/assets/app.js", nil))
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d", response.Code)
	}
	if got := response.Header().Get("Content-Type"); got != "text/javascript; charset=utf-8" && got != "text/javascript" {
		t.Fatalf("Content-Type = %q", got)
	}
	if response.Header().Get("Cache-Control") != "public, max-age=31536000, immutable" {
		t.Fatalf("Cache-Control = %q", response.Header().Get("Cache-Control"))
	}
}

func TestSPAUnavailableWhenIndexIsMissing(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	server := New(config.Config{Port: 8080}, logger, fstest.MapFS{}, http.NotFoundHandler())
	response := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/", nil))
	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", response.Code)
	}
}

func TestMethodNotAllowedForHealthEndpoint(t *testing.T) {
	server := testServer(t)
	response := httptest.NewRecorder()
	server.HTTP.Handler.ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/healthz", nil))
	if response.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", response.Code)
	}
}

func testServer(t *testing.T) *Server {
	t.Helper()
	assets := fstest.MapFS{
		"index.html":    &fstest.MapFile{Data: []byte("<main>app</main>")},
		"assets/app.js": &fstest.MapFile{Data: []byte("console.log('app')")},
	}
	var filesystem fs.FS = assets
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return New(config.Config{Port: 8080}, logger, filesystem, http.NotFoundHandler())
}
