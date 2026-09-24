package realtime

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
)

type Config struct {
	AllowedOrigins    map[string]struct{}
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	HeartbeatInterval time.Duration
	MaxMessageBytes   int64
	MaxConnections    int
	MessagesPerMinute int
}

type Handler struct {
	cfg      Config
	logger   *slog.Logger
	slots    chan struct{}
	active   atomic.Int64
	mu       sync.Mutex
	cancels  map[string]context.CancelFunc
	draining atomic.Bool
	wg       sync.WaitGroup
}

type inbound struct {
	envelope Envelope
	err      error
}

func NewHandler(cfg Config, logger *slog.Logger) *Handler {
	return &Handler{
		cfg:     cfg,
		logger:  logger,
		slots:   make(chan struct{}, cfg.MaxConnections),
		cancels: make(map[string]context.CancelFunc),
	}
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if _, ok := h.cfg.AllowedOrigins[r.Header.Get("Origin")]; !ok {
		http.Error(w, "origin not allowed", http.StatusForbidden)
		return
	}
	if h.draining.Load() {
		http.Error(w, "server shutting down", http.StatusServiceUnavailable)
		return
	}
	select {
	case h.slots <- struct{}{}:
		defer func() { <-h.slots }()
	default:
		http.Error(w, "server busy", http.StatusServiceUnavailable)
		return
	}

	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		h.logger.Warn("websocket upgrade failed", "error", err)
		return
	}
	defer func() { _ = conn.CloseNow() }()
	conn.SetReadLimit(h.cfg.MaxMessageBytes)

	connectionID, err := randomID()
	if err != nil {
		_ = conn.Close(websocket.StatusInternalError, "connection setup failed")
		return
	}
	h.active.Add(1)
	defer h.active.Add(-1)
	h.logger.Info("websocket connected", "connection_id", connectionID)
	defer h.logger.Info("websocket disconnected", "connection_id", connectionID)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()
	h.wg.Add(1)
	defer h.wg.Done()
	h.mu.Lock()
	h.cancels[connectionID] = cancel
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		delete(h.cancels, connectionID)
		h.mu.Unlock()
	}()

	hello, _ := NewEnvelope("connection.hello", "", HelloPayload{
		ConnectionID:    connectionID,
		ProtocolVersion: ProtocolVersion,
		HeartbeatMillis: h.cfg.HeartbeatInterval.Milliseconds(),
		ResumeSupported: false,
	})
	if err := h.write(ctx, conn, hello); err != nil {
		return
	}

	messages := make(chan inbound, 16)
	go h.readLoop(ctx, conn, messages)

	ticker := time.NewTicker(h.cfg.HeartbeatInterval)
	defer ticker.Stop()
	var sequence uint64

	for {
		select {
		case <-ctx.Done():
			_ = conn.Close(websocket.StatusGoingAway, "server shutting down")
			return
		case message := <-messages:
			if message.err != nil {
				h.closeForError(conn, message.err)
				return
			}
			if !h.handleMessage(ctx, conn, message.envelope) {
				return
			}
		case <-ticker.C:
			sequence++
			ping, _ := NewEnvelope("heartbeat.ping", "", HeartbeatPayload{Sequence: sequence})
			if err := h.write(ctx, conn, ping); err != nil {
				return
			}
		}
	}
}

func (h *Handler) Shutdown(ctx context.Context) error {
	h.draining.Store(true)
	h.mu.Lock()
	for _, cancel := range h.cancels {
		cancel()
	}
	h.mu.Unlock()

	done := make(chan struct{})
	go func() {
		h.wg.Wait()
		close(done)
	}()
	select {
	case <-done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (h *Handler) readLoop(ctx context.Context, conn *websocket.Conn, messages chan<- inbound) {
	windowStarted := time.Now()
	count := 0
	for {
		readCtx, cancel := context.WithTimeout(ctx, h.cfg.ReadTimeout)
		messageType, data, err := conn.Read(readCtx)
		cancel()
		if err != nil {
			select {
			case messages <- inbound{err: err}:
			case <-ctx.Done():
			}
			return
		}
		if messageType != websocket.MessageText {
			messages <- inbound{err: errors.New("binary messages are not supported")}
			return
		}
		if time.Since(windowStarted) >= time.Minute {
			windowStarted, count = time.Now(), 0
		}
		count++
		if count > h.cfg.MessagesPerMinute {
			messages <- inbound{err: errRateLimited}
			return
		}
		envelope, err := Decode(data)
		messages <- inbound{envelope: envelope, err: err}
		if err != nil {
			return
		}
	}
}

var errRateLimited = errors.New("message rate exceeded")

func (h *Handler) handleMessage(ctx context.Context, conn *websocket.Conn, envelope Envelope) bool {
	switch envelope.Type {
	case "heartbeat.pong":
		var payload HeartbeatPayload
		if err := json.Unmarshal(envelope.Payload, &payload); err != nil {
			h.writeProtocolError(ctx, conn, "invalid_payload", "Heartbeat payload is invalid.", envelope.ID)
			return false
		}
		return true
	case "connection.resume":
		var payload ResumePayload
		if err := json.Unmarshal(envelope.Payload, &payload); err != nil || payload.Token == "" {
			h.writeProtocolError(ctx, conn, "invalid_payload", "Resume payload is invalid.", envelope.ID)
			return false
		}
		response, _ := NewEnvelope("connection.resume_unavailable", envelope.ID, map[string]string{
			"reason": "Session state is not available in this version.",
		})
		return h.write(ctx, conn, response) == nil
	default:
		h.writeProtocolError(ctx, conn, "unknown_message_type", "Message type is not supported.", envelope.ID)
		return false
	}
}

func (h *Handler) writeProtocolError(ctx context.Context, conn *websocket.Conn, code, message, correlationID string) {
	envelope, _ := NewEnvelope("error", correlationID, ErrorPayload{
		Code: code, Message: message, CorrelationID: correlationID,
	})
	_ = h.write(ctx, conn, envelope)
}

func (h *Handler) write(ctx context.Context, conn *websocket.Conn, envelope Envelope) error {
	data, err := json.Marshal(envelope)
	if err != nil {
		return err
	}
	writeCtx, cancel := context.WithTimeout(ctx, h.cfg.WriteTimeout)
	defer cancel()
	return conn.Write(writeCtx, websocket.MessageText, data)
}

func (h *Handler) closeForError(conn *websocket.Conn, err error) {
	status, reason := websocket.StatusPolicyViolation, "invalid message"
	switch {
	case errors.Is(err, websocket.ErrMessageTooBig):
		status, reason = websocket.StatusMessageTooBig, "message too large"
	case errors.Is(err, errRateLimited):
		status, reason = websocket.StatusPolicyViolation, "message rate exceeded"
	case websocket.CloseStatus(err) != -1:
		return
	}
	_ = conn.Close(status, reason)
}

func randomID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(value[:]), nil
}
