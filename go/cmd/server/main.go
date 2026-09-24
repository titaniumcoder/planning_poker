package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/titaniumcoder/planning-poker/go/internal/config"
	"github.com/titaniumcoder/planning-poker/go/internal/httpserver"
	"github.com/titaniumcoder/planning-poker/go/internal/poker"
	"github.com/titaniumcoder/planning-poker/go/internal/realtime"
	webassets "github.com/titaniumcoder/planning-poker/go/internal/web"
)

func main() {
	os.Exit(run())
}

func run() int {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg, err := config.Load()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		return 1
	}
	assets, err := webassets.Assets()
	if err != nil {
		logger.Error("load embedded frontend", "error", err)
		return 1
	}
	realtimeHandler := realtime.NewHandler(realtime.Config{
		AllowedOrigins:    cfg.AllowedOrigins,
		ReadTimeout:       cfg.WebSocketReadTimeout,
		WriteTimeout:      cfg.WebSocketWriteTimeout,
		HeartbeatInterval: cfg.HeartbeatInterval,
		MaxMessageBytes:   cfg.MaxMessageBytes,
		MaxConnections:    cfg.MaxConnections,
		MessagesPerMinute: cfg.MessagesPerMinute,
	}, logger)
	server := httpserver.New(cfg, logger, assets, realtimeHandler, poker.NewStore())

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-ctx.Done()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
		defer cancel()
		if err := realtimeHandler.Shutdown(shutdownCtx); err != nil {
			logger.Error("websocket shutdown failed", "error", err)
		}
		if err := server.HTTP.Shutdown(shutdownCtx); err != nil {
			logger.Error("graceful shutdown failed", "error", err)
		}
	}()

	logger.Info("server starting", "address", server.HTTP.Addr, "environment", cfg.Environment)
	if err := server.HTTP.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("server stopped unexpectedly", "error", err)
		return 1
	}
	logger.Info("server stopped")
	return 0
}
