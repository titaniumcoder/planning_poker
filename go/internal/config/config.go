// Package config loads and validates runtime server configuration.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Port                  int
	Environment           string
	AppOrigin             string
	AllowedOrigins        map[string]struct{}
	HTTPReadTimeout       time.Duration
	HTTPReadHeaderTimeout time.Duration
	HTTPWriteTimeout      time.Duration
	HTTPIdleTimeout       time.Duration
	ShutdownTimeout       time.Duration
	WebSocketReadTimeout  time.Duration
	WebSocketWriteTimeout time.Duration
	HeartbeatInterval     time.Duration
	MaxMessageBytes       int64
	MaxConnections        int
	MessagesPerMinute     int
}

func Load() (Config, error) {
	cfg := Config{
		Port:                  8080,
		Environment:           env("APP_ENV", "development"),
		AppOrigin:             env("APP_ORIGIN", "http://localhost:5173"),
		HTTPReadTimeout:       10 * time.Second,
		HTTPReadHeaderTimeout: 5 * time.Second,
		HTTPWriteTimeout:      15 * time.Second,
		HTTPIdleTimeout:       60 * time.Second,
		ShutdownTimeout:       10 * time.Second,
		WebSocketReadTimeout:  45 * time.Second,
		WebSocketWriteTimeout: 5 * time.Second,
		HeartbeatInterval:     20 * time.Second,
		MaxMessageBytes:       16 * 1024,
		MaxConnections:        500,
		MessagesPerMinute:     120,
	}

	var err error
	if cfg.Port, err = intEnv("PORT", cfg.Port, 1, 65535); err != nil {
		return Config{}, err
	}
	if cfg.MaxConnections, err = intEnv("WS_MAX_CONNECTIONS", cfg.MaxConnections, 1, 100_000); err != nil {
		return Config{}, err
	}
	if cfg.MessagesPerMinute, err = intEnv("WS_MESSAGES_PER_MINUTE", cfg.MessagesPerMinute, 1, 100_000); err != nil {
		return Config{}, err
	}
	maxMessage, err := intEnv("WS_MAX_MESSAGE_BYTES", int(cfg.MaxMessageBytes), 256, 1<<20)
	if err != nil {
		return Config{}, err
	}
	cfg.MaxMessageBytes = int64(maxMessage)

	if cfg.Environment == "production" && os.Getenv("APP_ORIGIN") == "" {
		return Config{}, fmt.Errorf("APP_ORIGIN is required in production")
	}
	if !strings.HasPrefix(cfg.AppOrigin, "http://") && !strings.HasPrefix(cfg.AppOrigin, "https://") {
		return Config{}, fmt.Errorf("APP_ORIGIN must be an absolute http or https origin")
	}

	cfg.AppOrigin = strings.TrimRight(cfg.AppOrigin, "/")
	cfg.AllowedOrigins = map[string]struct{}{cfg.AppOrigin: {}}

	return cfg, nil
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func intEnv(name string, fallback, minimum, maximum int) (int, error) {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < minimum || value > maximum {
		return 0, fmt.Errorf("%s must be an integer between %d and %d", name, minimum, maximum)
	}
	return value, nil
}
