package loadtest_test

import (
	"context"
	"io"
	"log/slog"
	"net/http/httptest"
	"testing"
	"testing/fstest"
	"time"

	"github.com/titaniumcoder/planning-poker/go/internal/config"
	"github.com/titaniumcoder/planning-poker/go/internal/httpserver"
	"github.com/titaniumcoder/planning-poker/go/internal/loadtest"
	"github.com/titaniumcoder/planning-poker/go/internal/poker"
	"github.com/titaniumcoder/planning-poker/go/internal/realtime"
)

func TestRunCompletesConcurrentRooms(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	target := httptest.NewUnstartedServer(nil)
	targetURL := "http://" + target.Listener.Addr().String()
	realtimeHandler := realtime.NewHandler(realtime.Config{
		AllowedOrigins: map[string]struct{}{targetURL: {}}, ReadTimeout: time.Second,
		WriteTimeout: time.Second, HeartbeatInterval: 50 * time.Millisecond,
		MaxMessageBytes: 1024, MaxConnections: 100, MessagesPerMinute: 100,
	}, logger)
	server := httpserver.New(
		config.Config{Port: 8080, AppOrigin: targetURL},
		logger,
		fstest.MapFS{"index.html": &fstest.MapFile{Data: []byte("app")}},
		realtimeHandler,
		poker.NewStore(),
	)
	target.Config.Handler = server.HTTP.Handler
	target.Start()
	defer target.Close()

	report, err := loadtest.Run(context.Background(), loadtest.Config{
		TargetURL: target.URL, Rooms: 4, UsersMin: 3, UsersMax: 4, RoundsMin: 2, RoundsMax: 3,
		Seed: 42, WebSockets: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if report.RoomsSucceeded != 4 || report.Failures != 0 || len(report.Errors) != 0 {
		t.Fatalf("report = %#v", report)
	}
	if report.Users < 12 || report.Users > 16 || report.Rounds < 8 || report.Rounds > 12 {
		t.Fatalf("unexpected workload totals: %#v", report)
	}
	if report.WebSockets != report.Users {
		t.Fatalf("websockets = %d, users = %d", report.WebSockets, report.Users)
	}
	if report.Requests == 0 || report.P95 <= 0 || report.Duration <= 0 {
		t.Fatalf("missing metrics: %#v", report)
	}
}

func TestRunRejectsInvalidConfiguration(t *testing.T) {
	_, err := loadtest.Run(context.Background(), loadtest.Config{
		TargetURL: "http://example.test", Rooms: 1, UsersMin: 8, UsersMax: 3,
		RoundsMin: 1, RoundsMax: 1,
	})
	if err == nil {
		t.Fatal("Run accepted an invalid user range")
	}
}

func TestRunHonorsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	_, err := loadtest.Run(ctx, loadtest.Config{
		TargetURL: "http://127.0.0.1:1", Rooms: 1, UsersMin: 1, UsersMax: 1,
		RoundsMin: 1, RoundsMax: 1, DelayMin: time.Millisecond, DelayMax: time.Millisecond,
	})
	if err == nil {
		t.Fatal("Run did not return the context error")
	}
}
