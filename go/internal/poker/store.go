// Package poker contains the in-memory planning-poker domain.
package poker

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	ErrNotFound       = errors.New("poker session not found")
	ErrClosed         = errors.New("poker session is closed")
	ErrUnauthorized   = errors.New("not a member of this poker session")
	ErrNoParticipants = errors.New("no unmuted participants available for voting")
	ErrRoundActive    = errors.New("a voting session is already in progress")
	ErrNoRound        = errors.New("no voting is currently in progress")
)

var cards = map[string][]string{
	"fibonacci": {"?", "1", "2", "3", "5", "8", "13", "20", "40", "100"},
	"t-shirt":   {"?", "XS", "S", "M", "L", "XL", "XXL"},
}

type Store struct {
	mu       sync.RWMutex
	pokers   map[string]*Poker
	sessions map[string]sessionIdentity
	now      func() time.Time
}

type sessionIdentity struct {
	PokerID string
	Member  Member
}

type Poker struct {
	ID       string     `json:"id"`
	Name     string     `json:"name"`
	CardType string     `json:"cardType"`
	ClosedAt *time.Time `json:"closedAt,omitempty"`
	Members  []Member   `json:"members"`
	Votings  []Voting   `json:"votings"`
	Round    *Round     `json:"round,omitempty"`
}

type Member struct {
	Name   string `json:"name"`
	Online bool   `json:"online"`
	Muted  bool   `json:"muted"`
}

type Voting struct {
	ID       string     `json:"id"`
	Title    string     `json:"title"`
	Link     string     `json:"link,omitempty"`
	Decision string     `json:"decision,omitempty"`
	Position int        `json:"position"`
	Rounds   []Finished `json:"rounds"`
}

type Round struct {
	VotingID     string            `json:"votingId"`
	Participants []string          `json:"participants"`
	Votes        map[string]string `json:"votes"`
	EndsAt       time.Time         `json:"endsAt"`
}

type Finished struct {
	Result       string            `json:"result"`
	Votes        map[string]string `json:"votes"`
	Participants []string          `json:"participants"`
	EndedAt      time.Time         `json:"endedAt"`
}

func NewStore() *Store {
	return &Store{pokers: make(map[string]*Poker), sessions: make(map[string]sessionIdentity), now: time.Now}
}

func CardOptions(cardType string) []string {
	options, ok := cards[cardType]
	if !ok {
		options = cards["fibonacci"]
	}
	return append([]string(nil), options...)
}

func (s *Store) Create(name, username, cardType string) (Poker, string, error) {
	name, err := required(name, 100, "session name")
	if err != nil {
		return Poker{}, "", err
	}
	username, err = required(username, 100, "name")
	if err != nil {
		return Poker{}, "", err
	}
	if _, ok := cards[cardType]; !ok {
		return Poker{}, "", errors.New("card type must be fibonacci or t-shirt")
	}
	pokerID, err := newID()
	if err != nil {
		return Poker{}, "", err
	}
	token, err := newID()
	if err != nil {
		return Poker{}, "", err
	}
	poker := &Poker{ID: pokerID, Name: name, CardType: cardType, Members: []Member{{Name: username, Online: true}}}
	s.mu.Lock()
	s.pokers[pokerID], s.sessions[token] = poker, sessionIdentity{PokerID: pokerID, Member: Member{Name: username, Online: true}}
	s.mu.Unlock()
	return clonePoker(poker), token, nil
}

func (s *Store) Join(pokerID, username string) (Poker, string, error) {
	username, err := required(username, 100, "name")
	if err != nil {
		return Poker{}, "", err
	}
	token, err := newID()
	if err != nil {
		return Poker{}, "", err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	poker, ok := s.pokers[pokerID]
	if !ok {
		return Poker{}, "", ErrNotFound
	}
	for i := range poker.Members {
		if poker.Members[i].Name == username {
			return Poker{}, "", errors.New("username is already taken")
		}
	}
	poker.Members = append(poker.Members, Member{Name: username, Online: true})
	s.sessions[token] = sessionIdentity{PokerID: pokerID, Member: Member{Name: username, Online: true}}
	return clonePoker(poker), token, nil
}

func (s *Store) Get(pokerID, token string) (Poker, Member, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	poker, ok := s.pokers[pokerID]
	if !ok {
		return Poker{}, Member{}, ErrNotFound
	}
	identity, ok := s.sessions[token]
	if !ok || identity.PokerID != pokerID || !hasMember(poker, identity.Member.Name) {
		return Poker{}, Member{}, ErrUnauthorized
	}
	return clonePoker(poker), identity.Member, nil
}

func (s *Store) Leave(pokerID, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	poker, ok := s.pokers[pokerID]
	if !ok {
		return ErrNotFound
	}
	identity, ok := s.sessions[token]
	if !ok || identity.PokerID != pokerID || !hasMember(poker, identity.Member.Name) {
		return ErrUnauthorized
	}
	delete(s.sessions, token)
	for i := range poker.Members {
		if poker.Members[i].Name == identity.Member.Name {
			poker.Members[i].Online = false
		}
	}
	return nil
}

func (s *Store) AddVoting(pokerID, token, title, link string) (Poker, error) {
	title, err := required(title, 200, "voting title")
	if err != nil {
		return Poker{}, err
	}
	if err := validateLink(link); err != nil {
		return Poker{}, err
	}
	return s.mutate(pokerID, token, func(p *Poker, _ Member) error {
		if p.ClosedAt != nil {
			return ErrClosed
		}
		votingID, err := newID()
		if err != nil {
			return err
		}
		p.Votings = append(p.Votings, Voting{ID: votingID, Title: title, Link: strings.TrimSpace(link), Position: len(p.Votings) + 1})
		return nil
	})
}

func (s *Store) SetDecision(pokerID, token, votingID, decision string) (Poker, error) {
	decision = strings.TrimSpace(decision)
	if len(decision) > 100 {
		return Poker{}, errors.New("decision must be 100 characters or fewer")
	}
	return s.mutate(pokerID, token, func(p *Poker, _ Member) error {
		voting := findVoting(p, votingID)
		if voting == nil {
			return ErrNotFound
		}
		voting.Decision = decision
		return nil
	})
}

func (s *Store) ToggleMute(pokerID, token string) (Poker, error) {
	return s.mutate(pokerID, token, func(p *Poker, member Member) error {
		for i := range p.Members {
			if p.Members[i].Name == member.Name {
				p.Members[i].Muted = !p.Members[i].Muted
				return nil
			}
		}
		return ErrUnauthorized
	})
}

func (s *Store) ToggleClosed(pokerID, token string) (Poker, error) {
	return s.mutate(pokerID, token, func(p *Poker, _ Member) error {
		if p.ClosedAt == nil {
			now := s.now().UTC()
			p.ClosedAt, p.Round = &now, nil
		} else {
			p.ClosedAt = nil
		}
		return nil
	})
}

func (s *Store) Delete(pokerID, token string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	poker, ok := s.pokers[pokerID]
	if !ok {
		return ErrNotFound
	}
	identity, ok := s.sessions[token]
	if !ok || identity.PokerID != pokerID || !hasMember(poker, identity.Member.Name) {
		return ErrUnauthorized
	}
	if poker.ClosedAt == nil {
		return errors.New("close the session before deleting it")
	}
	delete(s.pokers, pokerID)
	for session, candidate := range s.sessions {
		if candidate.PokerID == pokerID {
			delete(s.sessions, session)
		}
	}
	return nil
}

func (s *Store) StartRound(pokerID, token, votingID string) (Poker, error) {
	return s.mutate(pokerID, token, func(p *Poker, _ Member) error {
		if p.ClosedAt != nil {
			return ErrClosed
		}
		if p.Round != nil {
			return ErrRoundActive
		}
		if findVoting(p, votingID) == nil {
			return ErrNotFound
		}
		participants := make([]string, 0, len(p.Members))
		for _, member := range p.Members {
			if member.Online && !member.Muted {
				participants = append(participants, member.Name)
			}
		}
		if len(participants) == 0 {
			return ErrNoParticipants
		}
		p.Round = &Round{VotingID: votingID, Participants: participants, Votes: make(map[string]string), EndsAt: s.now().Add(30 * time.Second).UTC()}
		return nil
	})
}

func (s *Store) Vote(pokerID, token, vote string) (Poker, error) {
	return s.mutate(pokerID, token, func(p *Poker, member Member) error {
		if p.Round == nil {
			return ErrNoRound
		}
		if !contains(p.Round.Participants, member.Name) {
			return errors.New("you are not a participant in this voting")
		}
		if !contains(CardOptions(p.CardType), vote) {
			return errors.New("vote is not available for this card set")
		}
		p.Round.Votes[member.Name] = vote
		if len(p.Round.Votes) == len(p.Round.Participants) {
			s.finishRound(p, "completed")
		}
		return nil
	})
}

func (s *Store) CancelRound(pokerID, token string) (Poker, error) {
	return s.mutate(pokerID, token, func(p *Poker, _ Member) error {
		if p.Round == nil {
			return ErrNoRound
		}
		s.finishRound(p, "cancelled")
		return nil
	})
}

func (s *Store) ExpireRounds() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, poker := range s.pokers {
		if poker.Round != nil && !s.now().Before(poker.Round.EndsAt) {
			s.finishRound(poker, "timeout")
		}
	}
}

func (s *Store) mutate(pokerID, token string, fn func(*Poker, Member) error) (Poker, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	poker, ok := s.pokers[pokerID]
	if !ok {
		return Poker{}, ErrNotFound
	}
	identity, ok := s.sessions[token]
	if !ok || identity.PokerID != pokerID || !hasMember(poker, identity.Member.Name) {
		return Poker{}, ErrUnauthorized
	}
	if err := fn(poker, identity.Member); err != nil {
		return Poker{}, err
	}
	return clonePoker(poker), nil
}

func (s *Store) finishRound(poker *Poker, result string) {
	round := poker.Round
	if round == nil {
		return
	}
	if len(round.Votes) > 0 {
		voting := findVoting(poker, round.VotingID)
		votes := mapsClone(round.Votes)
		voting.Rounds = append(voting.Rounds, Finished{Result: result, Votes: votes, Participants: append([]string(nil), round.Participants...), EndedAt: s.now().UTC()})
		if result == "completed" && voting.Decision == "" && allSame(votes) && firstVote(votes) != "?" {
			voting.Decision = firstVote(votes)
		}
	}
	poker.Round = nil
}

func findVoting(poker *Poker, id string) *Voting {
	for i := range poker.Votings {
		if poker.Votings[i].ID == id {
			return &poker.Votings[i]
		}
	}
	return nil
}

func clonePoker(p *Poker) Poker {
	clone := *p
	clone.Members = append([]Member(nil), p.Members...)
	clone.Votings = append([]Voting(nil), p.Votings...)
	for i := range clone.Votings {
		clone.Votings[i].Rounds = append([]Finished(nil), p.Votings[i].Rounds...)
	}
	if p.Round != nil {
		round := *p.Round
		round.Participants, round.Votes = append([]string(nil), p.Round.Participants...), mapsClone(p.Round.Votes)
		clone.Round = &round
	}
	return clone
}

func required(value string, maximum int, field string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", errors.New(field + " is required")
	}
	if len([]rune(value)) > maximum {
		return "", errors.New(field + " must be " + strconv.Itoa(maximum) + " characters or fewer")
	}
	return value, nil
}

func validateLink(value string) error {
	value = strings.TrimSpace(value)
	if len(value) > 500 {
		return errors.New("link must be 500 characters or fewer")
	}
	if value == "" {
		return nil
	}
	parsed, err := url.ParseRequestURI(value)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return errors.New("link must be a valid HTTP or HTTPS URL")
	}
	return nil
}

func newID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(value[:]), nil
}

func hasMember(poker *Poker, name string) bool {
	for _, member := range poker.Members {
		if member.Name == name {
			return true
		}
	}
	return false
}

func contains(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func mapsClone(values map[string]string) map[string]string {
	clone := make(map[string]string, len(values))
	for key, value := range values {
		clone[key] = value
	}
	return clone
}

func allSame(values map[string]string) bool {
	value := firstVote(values)
	for _, candidate := range values {
		if candidate != value {
			return false
		}
	}
	return true
}

func firstVote(values map[string]string) string {
	for _, value := range values {
		return value
	}
	return ""
}
