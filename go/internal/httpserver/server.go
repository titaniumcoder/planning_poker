// Package httpserver composes the HTTP API, middleware, and embedded SPA.
package httpserver

import (
	"crypto/rand"
	"encoding/hex"
	"io/fs"
	"log/slog"
	"mime"
	"net/http"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/titaniumcoder/planning-poker/go/internal/config"
	"github.com/titaniumcoder/planning-poker/go/internal/poker"
)

type Server struct {
	HTTP *http.Server
}

func New(cfg config.Config, logger *slog.Logger, assets fs.FS, realtime http.Handler, store *poker.Store) *Server {
	mux := http.NewServeMux()
	mux.Handle("/healthz", getOnly(text(http.StatusOK, "ok")))
	mux.Handle("/readyz", getOnly(text(http.StatusOK, "ready")))
	mux.Handle("/api/v1/ws", realtime)
	api := newAPI(store, strings.HasPrefix(cfg.AppOrigin, "https://"))
	mux.Handle("/api/v1/pokers", api)
	mux.Handle("/api/v1/pokers/", api)
	mux.HandleFunc("/api/", http.NotFound)
	mux.Handle("/", spaHandler(assets))

	handler := recoverPanic(logger, requestID(securityHeaders(logRequests(logger, mux))))
	return &Server{HTTP: &http.Server{
		Addr:              ":" + strconv.Itoa(cfg.Port),
		Handler:           handler,
		ReadTimeout:       cfg.HTTPReadTimeout,
		ReadHeaderTimeout: cfg.HTTPReadHeaderTimeout,
		WriteTimeout:      cfg.HTTPWriteTimeout,
		IdleTimeout:       cfg.HTTPIdleTimeout,
	}}
}

func text(status int, body string) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}
}

func getOnly(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", http.MethodGet)
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func spaHandler(assets fs.FS) http.Handler {
	fileServer := http.FileServerFS(assets)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestPath := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if requestPath == "." || requestPath == "" {
			requestPath = "index.html"
		}
		if info, err := fs.Stat(assets, requestPath); err == nil && !info.IsDir() {
			if strings.HasPrefix(requestPath, "assets/") {
				w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
			}
			if contentType := mime.TypeByExtension(path.Ext(requestPath)); contentType != "" {
				w.Header().Set("Content-Type", contentType)
			}
			fileServer.ServeHTTP(w, r)
			return
		}
		if _, err := fs.Stat(assets, "index.html"); err != nil {
			http.Error(w, "frontend is not built", http.StatusServiceUnavailable)
			return
		}
		index, err := fs.ReadFile(assets, "index.html")
		if err != nil {
			http.Error(w, "frontend is unavailable", http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-cache")
		_, _ = w.Write(index)
	})
}

func securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'")
		w.Header().Set("Referrer-Policy", "strict-origin-when-cross-origin")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		next.ServeHTTP(w, r)
	})
}

func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var value [12]byte
		if _, err := rand.Read(value[:]); err == nil {
			id := hex.EncodeToString(value[:])
			w.Header().Set("X-Request-ID", id)
			r.Header.Set("X-Request-ID", id)
		}
		next.ServeHTTP(w, r)
	})
}

func logRequests(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(started).Milliseconds())
	})
}

func recoverPanic(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				logger.Error("request panic", "error", recovered, "path", r.URL.Path)
				http.Error(w, "internal server error", http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}
