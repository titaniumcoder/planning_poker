package realtime

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/coder/websocket"
)

func TestHandlerRejectsOrigin(t *testing.T) {
	server := httptest.NewServer(testHandler())
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_, response, err := websocket.Dial(ctx, "ws"+server.URL[4:], &websocket.DialOptions{
		HTTPHeader: map[string][]string{"Origin": {"https://evil.example"}},
	})
	if err == nil {
		t.Fatal("Dial() error = nil")
	}
	if response == nil || response.StatusCode != 403 {
		t.Fatalf("status = %v, want 403", response)
	}
}

func TestHandlerHelloHeartbeatAndResume(t *testing.T) {
	server := httptest.NewServer(testHandler())
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+server.URL[4:], &websocket.DialOptions{
		HTTPHeader: map[string][]string{"Origin": {"http://localhost:5173"}},
	})
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer func() { _ = conn.CloseNow() }()

	hello := readEnvelope(t, ctx, conn)
	if hello.Type != "connection.hello" {
		t.Fatalf("hello type = %q", hello.Type)
	}

	resume, _ := NewEnvelope("connection.resume", "request-1", ResumePayload{Token: "opaque", LastSequence: 4})
	writeEnvelope(t, ctx, conn, resume)
	unavailable := readEnvelope(t, ctx, conn)
	if unavailable.Type != "connection.resume_unavailable" || unavailable.ID != "request-1" {
		t.Fatalf("resume response = %#v", unavailable)
	}

	ping := readEnvelope(t, ctx, conn)
	if ping.Type != "heartbeat.ping" {
		t.Fatalf("ping type = %q", ping.Type)
	}
	var payload HeartbeatPayload
	if err := json.Unmarshal(ping.Payload, &payload); err != nil {
		t.Fatal(err)
	}
	pong, _ := NewEnvelope("heartbeat.pong", "", payload)
	writeEnvelope(t, ctx, conn, pong)
}

func TestHandlerRejectsUnknownMessageWithCorrelatedError(t *testing.T) {
	server := httptest.NewServer(testHandler())
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+server.URL[4:], &websocket.DialOptions{
		HTTPHeader: map[string][]string{"Origin": {"http://localhost:5173"}},
	})
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer func() { _ = conn.CloseNow() }()
	_ = readEnvelope(t, ctx, conn)
	message, _ := NewEnvelope("connection.resumed", "correlation-1", map[string]string{"name": "alice"})
	writeEnvelope(t, ctx, conn, message)
	response := readEnvelope(t, ctx, conn)
	if response.Type != "error" || response.ID != "correlation-1" {
		t.Fatalf("error response = %#v", response)
	}
}

func TestHandlerRejectsMalformedHeartbeatPayload(t *testing.T) {
	server := httptest.NewServer(testHandler())
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, "ws"+server.URL[4:], &websocket.DialOptions{
		HTTPHeader: map[string][]string{"Origin": {"http://localhost:5173"}},
	})
	if err != nil {
		t.Fatalf("Dial() error = %v", err)
	}
	defer func() { _ = conn.CloseNow() }()
	_ = readEnvelope(t, ctx, conn)
	message := Envelope{Version: ProtocolVersion, Type: "heartbeat.pong", ID: "bad", Payload: []byte(`{"sequence":"not-a-number"}`)}
	writeEnvelope(t, ctx, conn, message)
	response := readEnvelope(t, ctx, conn)
	if response.Type != "error" || response.ID != "bad" {
		t.Fatalf("error response = %#v", response)
	}
}

func testHandler() *Handler {
	return NewHandler(Config{
		AllowedOrigins:    map[string]struct{}{"http://localhost:5173": {}},
		ReadTimeout:       time.Second,
		WriteTimeout:      time.Second,
		HeartbeatInterval: 20 * time.Millisecond,
		MaxMessageBytes:   1024,
		MaxConnections:    10,
		MessagesPerMinute: 20,
	}, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func readEnvelope(t *testing.T, ctx context.Context, conn *websocket.Conn) Envelope {
	t.Helper()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("Read() error = %v", err)
	}
	envelope, err := Decode(data)
	if err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	return envelope
}

func writeEnvelope(t *testing.T, ctx context.Context, conn *websocket.Conn, envelope Envelope) {
	t.Helper()
	data, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatalf("Write() error = %v", err)
	}
}
