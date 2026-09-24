package httpserver

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/titaniumcoder/planning-poker/go/internal/poker"
)

type api struct {
	store         *poker.Store
	secureCookies bool
}

func newAPI(store *poker.Store, secureCookies bool) *api {
	return &api{store: store, secureCookies: secureCookies}
}

func (a *api) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	parts := strings.Split(strings.TrimPrefix(r.URL.Path, "/api/v1/pokers"), "/")
	if r.URL.Path == "/api/v1/pokers" {
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		a.create(w, r)
		return
	}
	if len(parts) < 2 || parts[1] == "" {
		http.NotFound(w, r)
		return
	}
	id := parts[1]
	token := a.token(r, id)
	if len(parts) == 2 {
		if r.Method != http.MethodGet {
			methodNotAllowed(w)
			return
		}
		a.get(w, id, token)
		return
	}
	action := strings.Join(parts[2:], "/")
	switch action {
	case "join":
		a.join(w, r, id)
	case "leave":
		a.leave(w, r, id, token)
	case "votings":
		a.addVoting(w, r, id, token)
	case "decision":
		a.decision(w, r, id, token)
	case "mute":
		a.mute(w, r, id, token)
	case "session":
		a.session(w, r, id, token)
	case "round/start":
		a.startRound(w, r, id, token)
	case "round/vote":
		a.vote(w, r, id, token)
	case "round/cancel":
		a.cancelRound(w, r, id, token)
	default:
		http.NotFound(w, r)
	}
}

func (a *api) create(w http.ResponseWriter, r *http.Request) {
	var request struct {
		Name            string `json:"name"`
		Username        string `json:"username"`
		CardType        string `json:"cardType"`
		PrivacyAccepted bool   `json:"privacyAccepted"`
	}
	if !decode(w, r, &request) {
		return
	}
	if !request.PrivacyAccepted {
		writeError(w, http.StatusUnprocessableEntity, "You must agree to the data privacy policy")
		return
	}
	if request.CardType == "" {
		request.CardType = "fibonacci"
	}
	session, token, err := a.store.Create(request.Name, request.Username, request.CardType)
	if err != nil {
		writeDomainError(w, err)
		return
	}
	a.setToken(w, session.ID, token)
	writeJSON(w, http.StatusCreated, session)
}

func (a *api) join(w http.ResponseWriter, r *http.Request, id string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var request struct {
		Username        string `json:"username"`
		PrivacyAccepted bool   `json:"privacyAccepted"`
	}
	if !decode(w, r, &request) {
		return
	}
	if !request.PrivacyAccepted {
		writeError(w, http.StatusUnprocessableEntity, "You must agree to the data privacy policy")
		return
	}
	session, token, err := a.store.Join(id, request.Username)
	if err != nil {
		writeDomainError(w, err)
		return
	}
	a.setToken(w, id, token)
	writeJSON(w, http.StatusOK, session)
}

func (a *api) get(w http.ResponseWriter, id, token string) {
	a.store.ExpireRounds()
	session, member, err := a.store.Get(id, token)
	if err != nil {
		writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, struct {
		Poker poker.Poker  `json:"poker"`
		User  poker.Member `json:"user"`
		Cards []string     `json:"cards"`
	}{Poker: session, User: member, Cards: poker.CardOptions(session.CardType)})
}

func (a *api) leave(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	if err := a.store.Leave(id, token); err != nil {
		writeDomainError(w, err)
		return
	}
	// #nosec G124 -- development runs on HTTP; production enables Secure from APP_ORIGIN.
	http.SetCookie(w, &http.Cookie{Name: cookieName(id), Value: "", Path: "/", MaxAge: -1, HttpOnly: true, Secure: a.secureCookies, SameSite: http.SameSiteLaxMode})
	w.WriteHeader(http.StatusNoContent)
}

func (a *api) addVoting(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var request struct{ Title, Link string }
	if !decode(w, r, &request) {
		return
	}
	session, err := a.store.AddVoting(id, token, request.Title, request.Link)
	a.writePoker(w, session, err)
}

func (a *api) decision(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPut {
		methodNotAllowed(w)
		return
	}
	var request struct{ VotingID, Decision string }
	if !decode(w, r, &request) {
		return
	}
	session, err := a.store.SetDecision(id, token, request.VotingID, request.Decision)
	a.writePoker(w, session, err)
}

func (a *api) mute(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	session, err := a.store.ToggleMute(id, token)
	a.writePoker(w, session, err)
}

func (a *api) session(w http.ResponseWriter, r *http.Request, id, token string) {
	switch r.Method {
	case http.MethodPost:
		session, err := a.store.ToggleClosed(id, token)
		a.writePoker(w, session, err)
	case http.MethodDelete:
		if err := a.store.Delete(id, token); err != nil {
			writeDomainError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		methodNotAllowed(w)
	}
}

func (a *api) startRound(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var request struct{ VotingID string }
	if !decode(w, r, &request) {
		return
	}
	session, err := a.store.StartRound(id, token, request.VotingID)
	a.writePoker(w, session, err)
}

func (a *api) vote(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	var request struct{ Vote string }
	if !decode(w, r, &request) {
		return
	}
	session, err := a.store.Vote(id, token, request.Vote)
	a.writePoker(w, session, err)
}

func (a *api) cancelRound(w http.ResponseWriter, r *http.Request, id, token string) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	session, err := a.store.CancelRound(id, token)
	a.writePoker(w, session, err)
}

func (a *api) writePoker(w http.ResponseWriter, session poker.Poker, err error) {
	if err != nil {
		writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

func (a *api) token(r *http.Request, id string) string {
	cookie, err := r.Cookie(cookieName(id))
	if err != nil {
		return ""
	}
	return cookie.Value
}

func (a *api) setToken(w http.ResponseWriter, id, token string) {
	// #nosec G124 -- development runs on HTTP; production enables Secure from APP_ORIGIN.
	http.SetCookie(w, &http.Cookie{Name: cookieName(id), Value: token, Path: "/", HttpOnly: true, Secure: a.secureCookies, SameSite: http.SameSiteLaxMode, MaxAge: int((24 * time.Hour).Seconds())})
}

func cookieName(id string) string { return "pp_" + id }

func decode(w http.ResponseWriter, r *http.Request, destination any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 8<<10)
	defer func() { _ = r.Body.Close() }()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON request")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeDomainError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, poker.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, poker.ErrUnauthorized):
		writeError(w, http.StatusUnauthorized, err.Error())
	case errors.Is(err, poker.ErrClosed), errors.Is(err, poker.ErrNoParticipants), errors.Is(err, poker.ErrRoundActive), errors.Is(err, poker.ErrNoRound):
		writeError(w, http.StatusConflict, err.Error())
	default:
		writeError(w, http.StatusUnprocessableEntity, err.Error())
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func methodNotAllowed(w http.ResponseWriter) {
	w.Header().Set("Allow", "GET, POST, PUT, DELETE")
	writeError(w, http.StatusMethodNotAllowed, "method not allowed")
}
