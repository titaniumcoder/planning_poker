package httpserver

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"testing"

	"github.com/titaniumcoder/planning-poker/go/internal/poker"
)

func TestPokerAPICompleteVotingFlow(t *testing.T) {
	server := httptest.NewServer(newAPI(poker.NewStore(), false))
	defer server.Close()
	ada := newClient(t)
	created := createPoker(t, ada, server.URL, "Sprint", "Ada")
	joiner := newClient(t)
	_ = joinPoker(t, joiner, server.URL, created.ID, "Bob")

	created = requestJSON[poker.Poker](t, ada, http.MethodPost, server.URL+"/api/v1/pokers/"+created.ID+"/votings", map[string]string{"title": "Login", "link": "https://example.test/login"}, http.StatusOK)
	votingID := created.Votings[0].ID
	_ = requestJSON[poker.Poker](t, ada, http.MethodPost, server.URL+"/api/v1/pokers/"+created.ID+"/round/start", map[string]string{"votingId": votingID}, http.StatusOK)
	_ = requestJSON[poker.Poker](t, ada, http.MethodPost, server.URL+"/api/v1/pokers/"+created.ID+"/round/vote", map[string]string{"vote": "3"}, http.StatusOK)
	finished := requestJSON[poker.Poker](t, joiner, http.MethodPost, server.URL+"/api/v1/pokers/"+created.ID+"/round/vote", map[string]string{"vote": "3"}, http.StatusOK)
	if finished.Round != nil || finished.Votings[0].Decision != "3" || len(finished.Votings[0].Rounds) != 1 {
		t.Fatalf("finished session = %#v", finished)
	}
}

func TestPokerAPIRejectsInvalidCreationAndUnauthorizedRead(t *testing.T) {
	server := httptest.NewServer(newAPI(poker.NewStore(), false))
	defer server.Close()
	client := newClient(t)
	requestJSON[map[string]string](t, client, http.MethodPost, server.URL+"/api/v1/pokers", map[string]any{"name": "Sprint", "username": "Ada", "privacyAccepted": false}, http.StatusUnprocessableEntity)
	created := createPoker(t, client, server.URL, "Sprint", "Ada")
	outsider := newClient(t)
	requestJSON[map[string]string](t, outsider, http.MethodGet, server.URL+"/api/v1/pokers/"+created.ID, nil, http.StatusUnauthorized)
}

func TestPokerAPIClosesThenDeletesSession(t *testing.T) {
	server := httptest.NewServer(newAPI(poker.NewStore(), false))
	defer server.Close()
	client := newClient(t)
	created := createPoker(t, client, server.URL, "Sprint", "Ada")
	closed := requestJSON[poker.Poker](t, client, http.MethodPost, server.URL+"/api/v1/pokers/"+created.ID+"/session", nil, http.StatusOK)
	if closed.ClosedAt == nil {
		t.Fatal("session was not closed")
	}
	requestJSON[any](t, client, http.MethodDelete, server.URL+"/api/v1/pokers/"+created.ID+"/session", nil, http.StatusNoContent)
	requestJSON[map[string]string](t, client, http.MethodGet, server.URL+"/api/v1/pokers/"+created.ID, nil, http.StatusNotFound)
}

func newClient(t *testing.T) *http.Client {
	t.Helper()
	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	return &http.Client{Jar: jar}
}

func createPoker(t *testing.T, client *http.Client, base, name, username string) poker.Poker {
	t.Helper()
	return requestJSON[poker.Poker](t, client, http.MethodPost, base+"/api/v1/pokers", map[string]any{"name": name, "username": username, "cardType": "fibonacci", "privacyAccepted": true}, http.StatusCreated)
}

func joinPoker(t *testing.T, client *http.Client, base, id, username string) poker.Poker {
	t.Helper()
	return requestJSON[poker.Poker](t, client, http.MethodPost, base+"/api/v1/pokers/"+id+"/join", map[string]any{"username": username, "privacyAccepted": true}, http.StatusOK)
}

func requestJSON[T any](t *testing.T, client *http.Client, method, address string, body any, status int) T {
	t.Helper()
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatal(err)
		}
		reader = bytes.NewReader(data)
	}
	request, err := http.NewRequest(method, address, reader)
	if err != nil {
		t.Fatal(err)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = response.Body.Close() }()
	if response.StatusCode != status {
		data, _ := io.ReadAll(response.Body)
		t.Fatalf("%s %s status = %d, want %d: %s", method, address, response.StatusCode, status, data)
	}
	var result T
	if status != http.StatusNoContent {
		if err := json.NewDecoder(response.Body).Decode(&result); err != nil {
			t.Fatal(err)
		}
	}
	return result
}
