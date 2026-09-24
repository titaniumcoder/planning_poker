package config

import "testing"

func TestLoadDefaults(t *testing.T) {
	t.Setenv("APP_ENV", "")
	t.Setenv("APP_ORIGIN", "")
	t.Setenv("PORT", "")

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
}

func TestLoadRequiresProductionOrigin(t *testing.T) {
	t.Setenv("APP_ENV", "production")
	t.Setenv("APP_ORIGIN", "")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want production origin error")
	}
}

func TestLoadRejectsInvalidValues(t *testing.T) {
	t.Setenv("PORT", "70000")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want invalid port error")
	}
}
