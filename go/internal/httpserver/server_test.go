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
