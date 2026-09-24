// Package loadtest drives realistic multi-room workloads against a running server.
package loadtest

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"
	"github.com/titaniumcoder/planning-poker/go/internal/realtime"
)

type Config struct {
	TargetURL  string
	Rooms      int
	UsersMin   int
	UsersMax   int
	RoundsMin  int
	RoundsMax  int
	DelayMin   time.Duration
	DelayMax   time.Duration
	RoomRamp   time.Duration
	WebSockets bool
	Seed       uint64
	HTTPClient *http.Client
}

type Report struct {
	RoomsRequested int           `json:"roomsRequested"`
	RoomsSucceeded int           `json:"roomsSucceeded"`
	Users          int64         `json:"users"`
	Rounds         int64         `json:"rounds"`
	Requests       int64         `json:"requests"`
	WebSockets     int64         `json:"webSockets"`
	Failures       int64         `json:"failures"`
	ErrorRate      float64       `json:"errorRate"`
	Duration       time.Duration `json:"-"`
	P50            time.Duration `json:"-"`
	P95            time.Duration `json:"-"`
	P99            time.Duration `json:"-"`
	DurationMillis float64       `json:"durationMillis"`
	P50Millis      float64       `json:"p50Millis"`
	P95Millis      float64       `json:"p95Millis"`
	P99Millis      float64       `json:"p99Millis"`
	Errors         []string      `json:"errors,omitempty"`
}

type runner struct {
	cfg         Config
	target      *url.URL
	transport   http.RoundTripper
	requests    atomic.Int64
	webSockets  atomic.Int64
	failures    atomic.Int64
	users       atomic.Int64
	rounds      atomic.Int64
	rooms       atomic.Int64
	mu          sync.Mutex
	latencies   []time.Duration
	errorCounts map[string]int
}

type pokerState struct {
	ID       string `json:"id"`
	CardType string `json:"cardType"`
	Round    *struct {
		VotingID string `json:"votingId"`
	} `json:"round,omitempty"`
	Votings []struct {
		ID       string `json:"id"`
		Decision string `json:"decision,omitempty"`
		Rounds   []struct {
			Result string            `json:"result"`
			Votes  map[string]string `json:"votes"`
		} `json:"rounds"`
	} `json:"votings"`
}

type snapshot struct {
	Poker pokerState `json:"poker"`
}

type socketClient struct {
	conn   *websocket.Conn
	cancel context.CancelFunc
	done   chan struct{}
}

func Run(ctx context.Context, cfg Config) (Report, error) {
	if err := validate(cfg); err != nil {
		return Report{}, err
	}
	target, err := url.Parse(cfg.TargetURL)
	if err != nil {
		return Report{}, fmt.Errorf("parse target URL: %w", err)
	}
	transport := http.DefaultTransport
	if defaultTransport, ok := http.DefaultTransport.(*http.Transport); ok {
		tuned := defaultTransport.Clone()
		tuned.MaxIdleConns = cfg.Rooms * cfg.UsersMax
		tuned.MaxIdleConnsPerHost = cfg.Rooms * cfg.UsersMax
		transport = tuned
	}
	if cfg.HTTPClient != nil && cfg.HTTPClient.Transport != nil {
		transport = cfg.HTTPClient.Transport
	}
	workload := &runner{cfg: cfg, target: target, transport: transport, errorCounts: make(map[string]int)}
	started := time.Now()
	var wait sync.WaitGroup
	for roomIndex := range cfg.Rooms {
		wait.Add(1)
		go func() {
			defer wait.Done()
			if !workload.waitForRamp(ctx, roomIndex) {
				return
			}
			if err := workload.runRoom(ctx, roomIndex); err != nil {
				workload.recordError(err)
			}
		}()
	}
	wait.Wait()
	report := workload.report(time.Since(started))
	if ctx.Err() != nil {
		return report, ctx.Err()
	}
	return report, nil
}

func (r *runner) runRoom(ctx context.Context, roomIndex int) error {
	// #nosec G404 G115 -- deterministic seeds are reproducible and roomIndex is nonnegative.
	random := rand.New(rand.NewPCG(r.cfg.Seed+uint64(roomIndex), r.cfg.Seed^uint64(roomIndex+1)))
	userCount := between(random, r.cfg.UsersMin, r.cfg.UsersMax)
	roundCount := between(random, r.cfg.RoundsMin, r.cfg.RoundsMax)
	cardType := "fibonacci"
	cards := []string{"1", "2", "3", "5", "8", "13"}
	if random.IntN(2) == 1 {
		cardType, cards = "t-shirt", []string{"XS", "S", "M", "L", "XL"}
	}
	clients := make([]*http.Client, 0, userCount)
	sockets := make([]*socketClient, 0, userCount)
	defer func() {
		for _, socket := range sockets {
			socket.close()
		}
	}()
	for range userCount {
		client, err := r.newClient()
		if err != nil {
			return err
		}
		clients = append(clients, client)
	}

	var state pokerState
	if err := r.post(ctx, clients[0], "/api/v1/pokers", map[string]any{
		"name": "Load room " + fmt.Sprint(roomIndex), "username": username(roomIndex, 0),
		"cardType": cardType, "privacyAccepted": true,
	}, http.StatusCreated, &state); err != nil {
		return fmt.Errorf("room %d create: %w", roomIndex, err)
	}
	if r.cfg.WebSockets {
		socket, err := r.connectSocket(ctx)
		if err != nil {
			return fmt.Errorf("room %d owner websocket: %w", roomIndex, err)
		}
		sockets = append(sockets, socket)
	}
	r.users.Add(int64(userCount))

	for userIndex := 1; userIndex < userCount; userIndex++ {
		r.delay(ctx, random)
		if err := r.post(ctx, clients[userIndex], "/api/v1/pokers/"+state.ID+"/join", map[string]any{
			"username": username(roomIndex, userIndex), "privacyAccepted": true,
		}, http.StatusOK, &pokerState{}); err != nil {
			return fmt.Errorf("room %d join user %d: %w", roomIndex, userIndex, err)
		}
		if r.cfg.WebSockets {
			socket, err := r.connectSocket(ctx)
			if err != nil {
				return fmt.Errorf("room %d user %d websocket: %w", roomIndex, userIndex, err)
			}
			sockets = append(sockets, socket)
		}
	}

	for roundIndex := range roundCount {
		r.delay(ctx, random)
		if err := r.post(ctx, clients[0], "/api/v1/pokers/"+state.ID+"/votings", map[string]string{
			"title": fmt.Sprintf("Story %d", roundIndex+1),
			"link":  fmt.Sprintf("https://example.test/story/%d/%d", roomIndex, roundIndex),
		}, http.StatusOK, &state); err != nil {
			return fmt.Errorf("room %d round %d create voting: %w", roomIndex, roundIndex, err)
		}
		votingID := state.Votings[len(state.Votings)-1].ID
		if err := r.post(ctx, clients[0], "/api/v1/pokers/"+state.ID+"/round/start", map[string]string{
			"votingId": votingID,
		}, http.StatusOK, &state); err != nil {
			return fmt.Errorf("room %d round %d start: %w", roomIndex, roundIndex, err)
		}
		card := cards[random.IntN(len(cards))]
		for userIndex, client := range clients {
			r.delay(ctx, random)
			if err := r.post(ctx, client, "/api/v1/pokers/"+state.ID+"/round/vote", map[string]string{
				"vote": card,
			}, http.StatusOK, &state); err != nil {
				return fmt.Errorf("room %d round %d vote user %d: %w", roomIndex, roundIndex, userIndex, err)
			}
		}
		r.rounds.Add(1)
	}

	var final snapshot
	if err := r.get(ctx, clients[0], "/api/v1/pokers/"+state.ID, &final); err != nil {
		return fmt.Errorf("room %d final state: %w", roomIndex, err)
	}
	if err := verify(final.Poker, roundCount, userCount); err != nil {
		return fmt.Errorf("room %d verification: %w", roomIndex, err)
	}
	r.rooms.Add(1)
	return nil
}

func (r *runner) newClient() (*http.Client, error) {
	jar, err := cookiejar.New(nil)
	if err != nil {
		return nil, fmt.Errorf("create cookie jar: %w", err)
	}
	return &http.Client{Transport: r.transport, Jar: jar, Timeout: 30 * time.Second}, nil
}

func (r *runner) post(
	ctx context.Context,
	client *http.Client,
	path string,
	body any,
	expectedStatus int,
	destination any,
) error {
	return r.do(ctx, client, http.MethodPost, path, body, expectedStatus, destination)
}

func (r *runner) get(ctx context.Context, client *http.Client, path string, destination any) error {
	return r.do(ctx, client, http.MethodGet, path, nil, http.StatusOK, destination)
}

func (r *runner) do(
	ctx context.Context,
	client *http.Client,
	method, path string,
	body any,
	expectedStatus int,
	destination any,
) error {
	var requestBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encode request: %w", err)
		}
		requestBody = bytes.NewReader(data)
	}
	requestURL := r.target.ResolveReference(&url.URL{Path: path})
	request, err := http.NewRequestWithContext(ctx, method, requestURL.String(), requestBody)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	started := time.Now()
	response, err := client.Do(request)
	r.recordRequest(time.Since(started), err != nil)
	if err != nil {
		return fmt.Errorf("%s %s: %w", method, path, err)
	}
	defer func() { _ = response.Body.Close() }()
	data, err := io.ReadAll(io.LimitReader(response.Body, 1<<20))
	if err != nil {
		r.failures.Add(1)
		return fmt.Errorf("read response: %w", err)
	}
	if response.StatusCode != expectedStatus {
		r.failures.Add(1)
		return fmt.Errorf("status %d: %s", response.StatusCode, string(data))
	}
	if destination != nil && len(data) > 0 {
		if err := json.Unmarshal(data, destination); err != nil {
			r.failures.Add(1)
			return fmt.Errorf("decode response: %w", err)
		}
	}
	return nil
}

func (r *runner) recordRequest(latency time.Duration, failed bool) {
	r.requests.Add(1)
	if failed {
		r.failures.Add(1)
	}
	r.mu.Lock()
	r.latencies = append(r.latencies, latency)
	r.mu.Unlock()
}

func (r *runner) recordError(err error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	const maxErrorSamples = 10
	if _, exists := r.errorCounts[err.Error()]; !exists && len(r.errorCounts) >= maxErrorSamples {
		r.errorCounts["additional errors omitted"]++
		return
	}
	r.errorCounts[err.Error()]++
}

func (r *runner) report(duration time.Duration) Report {
	r.mu.Lock()
	latencies := append([]time.Duration(nil), r.latencies...)
	errorsList := make([]string, 0, len(r.errorCounts))
	for message, count := range r.errorCounts {
		errorsList = append(errorsList, fmt.Sprintf("%dx %s", count, message))
	}
	r.mu.Unlock()
	sort.Slice(latencies, func(i, j int) bool { return latencies[i] < latencies[j] })
	sort.Strings(errorsList)
	requests, failures := r.requests.Load(), r.failures.Load()
	errorRate := 0.0
	if requests > 0 {
		errorRate = float64(failures) / float64(requests)
	}
	p50, p95, p99 := percentile(latencies, 0.50), percentile(latencies, 0.95), percentile(latencies, 0.99)
	return Report{
		RoomsRequested: r.cfg.Rooms, RoomsSucceeded: int(r.rooms.Load()), Users: r.users.Load(),
		Rounds: r.rounds.Load(), Requests: requests, WebSockets: r.webSockets.Load(),
		Failures: failures, ErrorRate: errorRate,
		Duration: duration, P50: p50, P95: p95, P99: p99,
		DurationMillis: milliseconds(duration), P50Millis: milliseconds(p50),
		P95Millis: milliseconds(p95), P99Millis: milliseconds(p99), Errors: errorsList,
	}
}

func validate(cfg Config) error {
	switch {
	case cfg.TargetURL == "":
		return errors.New("target URL is required")
	case cfg.Rooms < 1:
		return errors.New("rooms must be positive")
	case cfg.UsersMin < 1 || cfg.UsersMax < cfg.UsersMin:
		return errors.New("invalid user range")
	case cfg.RoundsMin < 1 || cfg.RoundsMax < cfg.RoundsMin:
		return errors.New("invalid round range")
	case cfg.DelayMin < 0 || cfg.DelayMax < cfg.DelayMin:
		return errors.New("invalid delay range")
	case cfg.RoomRamp < 0:
		return errors.New("room ramp cannot be negative")
	default:
		return nil
	}
}

func verify(state pokerState, rounds, users int) error {
	if state.Round != nil || len(state.Votings) != rounds {
		return fmt.Errorf("got %d votings and active round %t, want %d completed", len(state.Votings), state.Round != nil, rounds)
	}
	for index, voting := range state.Votings {
		if len(voting.Rounds) != 1 || voting.Rounds[0].Result != "completed" ||
			len(voting.Rounds[0].Votes) != users || voting.Decision == "" {
			return fmt.Errorf("voting %d has incomplete result", index)
		}
	}
	return nil
}

func percentile(values []time.Duration, fraction float64) time.Duration {
	if len(values) == 0 {
		return 0
	}
	index := int(float64(len(values)-1) * fraction)
	return values[index]
}

func milliseconds(value time.Duration) float64 {
	return float64(value) / float64(time.Millisecond)
}

func between(random *rand.Rand, minimum, maximum int) int {
	return minimum + random.IntN(maximum-minimum+1)
}

func username(room, user int) string {
	return fmt.Sprintf("user-%d-%d", room, user)
}

func (r *runner) delay(ctx context.Context, random *rand.Rand) {
	if r.cfg.DelayMax == 0 {
		return
	}
	delay := r.cfg.DelayMin
	if difference := r.cfg.DelayMax - r.cfg.DelayMin; difference > 0 {
		delay += time.Duration(random.Int64N(int64(difference) + 1))
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
	case <-timer.C:
	}
}

func (r *runner) waitForRamp(ctx context.Context, roomIndex int) bool {
	if r.cfg.RoomRamp == 0 || roomIndex == 0 {
		return true
	}
	delay := time.Duration(roomIndex) * r.cfg.RoomRamp / time.Duration(r.cfg.Rooms-1)
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}

func (r *runner) connectSocket(ctx context.Context) (*socketClient, error) {
	socketURL := *r.target
	socketURL.Path = "/api/v1/ws"
	switch socketURL.Scheme {
	case "http":
		socketURL.Scheme = "ws"
	case "https":
		socketURL.Scheme = "wss"
	default:
		return nil, fmt.Errorf("unsupported target scheme %q", socketURL.Scheme)
	}
	origin := r.target.Scheme + "://" + r.target.Host
	started := time.Now()
	conn, response, err := websocket.Dial(ctx, socketURL.String(), &websocket.DialOptions{
		HTTPHeader: http.Header{"Origin": []string{origin}},
	})
	r.recordRequest(time.Since(started), err != nil)
	if err != nil {
		if response != nil {
			return nil, fmt.Errorf("handshake status %d: %w", response.StatusCode, err)
		}
		return nil, fmt.Errorf("connect: %w", err)
	}
	helloCtx, cancelHello := context.WithTimeout(ctx, 5*time.Second)
	_, data, err := conn.Read(helloCtx)
	cancelHello()
	if err != nil {
		_ = conn.CloseNow()
		r.failures.Add(1)
		return nil, fmt.Errorf("read hello: %w", err)
	}
	envelope, err := realtime.Decode(data)
	if err != nil || envelope.Type != "connection.hello" {
		_ = conn.CloseNow()
		r.failures.Add(1)
		return nil, errors.New("invalid connection hello")
	}
	socketCtx, cancel := context.WithCancel(ctx)
	client := &socketClient{conn: conn, cancel: cancel, done: make(chan struct{})}
	r.webSockets.Add(1)
	go r.readSocket(socketCtx, client)
	return client, nil
}

func (r *runner) readSocket(ctx context.Context, client *socketClient) {
	defer close(client.done)
	for {
		_, data, err := client.conn.Read(ctx)
		if err != nil {
			if ctx.Err() == nil && websocket.CloseStatus(err) == -1 {
				r.failures.Add(1)
				r.recordError(fmt.Errorf("websocket read: %w", err))
			}
			return
		}
		envelope, err := realtime.Decode(data)
		if err != nil {
			r.failures.Add(1)
			r.recordError(fmt.Errorf("websocket decode: %w", err))
			return
		}
		if envelope.Type == "heartbeat.ping" {
			pong, envelopeErr := realtime.NewEnvelope("heartbeat.pong", "", json.RawMessage(envelope.Payload))
			if envelopeErr != nil {
				r.failures.Add(1)
				return
			}
			payload, marshalErr := json.Marshal(pong)
			if marshalErr != nil {
				r.failures.Add(1)
				return
			}
			writeCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			writeErr := client.conn.Write(writeCtx, websocket.MessageText, payload)
			cancel()
			if writeErr != nil {
				r.failures.Add(1)
				r.recordError(fmt.Errorf("websocket pong: %w", writeErr))
				return
			}
		}
	}
}

func (client *socketClient) close() {
	client.cancel()
	_ = client.conn.Close(websocket.StatusNormalClosure, "load session complete")
	select {
	case <-client.done:
	case <-time.After(time.Second):
		_ = client.conn.CloseNow()
	}
}
