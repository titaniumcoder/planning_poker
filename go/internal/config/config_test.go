package config

import (
	"strings"
	"testing"
	"time"
)

func TestLoadDefaults(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("APP_ORIGIN", "")
	t.Setenv("PORT", "")
	t.Setenv("WS_MAX_CONNECTIONS", "")
	t.Setenv("WS_MESSAGES_PER_MINUTE", "")
	t.Setenv("WS_MAX_MESSAGE_BYTES", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.Port != 8080 {
		t.Fatalf("Port = %d, want 8080", cfg.Port)
	}
	if _, ok := cfg.AllowedOrigins["http://localhost:5173"]; !ok {
		t.Fatal("development origin is not allowed")
	}
	if cfg.HeartbeatInterval != 20*time.Second || cfg.MaxMessageBytes != 16*1024 {
		t.Fatalf("unexpected realtime defaults: heartbeat=%s max_message_bytes=%d", cfg.HeartbeatInterval, cfg.MaxMessageBytes)
	}
}

func TestLoadRequiresProductionOrigin(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("APP_ORIGIN", "")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want production origin error")
	}
}

func TestLoadNormalizesOriginAndParsesLimits(t *testing.T) {
	t.Setenv("APP_ORIGIN", " https://poker.example/ ")
	t.Setenv("PORT", "9090")
	t.Setenv("WS_MAX_CONNECTIONS", "42")
	t.Setenv("WS_MESSAGES_PER_MINUTE", "60")
	t.Setenv("WS_MAX_MESSAGE_BYTES", "2048")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}
	if cfg.AppOrigin != "https://poker.example" {
		t.Fatalf("AppOrigin = %q", cfg.AppOrigin)
	}
	if cfg.Port != 9090 || cfg.MaxConnections != 42 || cfg.MessagesPerMinute != 60 || cfg.MaxMessageBytes != 2048 {
		t.Fatalf("parsed limits = %#v", cfg)
	}
	if _, ok := cfg.AllowedOrigins["https://poker.example"]; !ok {
		t.Fatal("normalized origin is not allowed")
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	tests := []struct {
		name string
		key  string
		raw  string
	}{
		{"port above maximum", "PORT", "70000"},
		{"port below minimum", "PORT", "0"},
		{"port not an integer", "PORT", "http"},
		{"connection limit below minimum", "WS_MAX_CONNECTIONS", "0"},
		{"message rate below minimum", "WS_MESSAGES_PER_MINUTE", "0"},
		{"message size below minimum", "WS_MAX_MESSAGE_BYTES", "255"},
		{"message size above maximum", "WS_MAX_MESSAGE_BYTES", "1048577"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv(tt.key, tt.raw)
			if _, err := Load(); err == nil || !strings.Contains(err.Error(), tt.key) {
				t.Fatalf("Load() error = %v, want error mentioning %s", err, tt.key)
			}
		})
	}
}

func TestLoadRejectsNonHTTPOrigin(t *testing.T) {
	for _, origin := range []string{"localhost:5173", "ftp://poker.example", "://bad"} {
		t.Run(origin, func(t *testing.T) {
			t.Setenv("APP_ORIGIN", origin)
			if _, err := Load(); err == nil {
				t.Fatalf("Load() error = nil for origin %q", origin)
			}
		})
	}
}
