package poker

import (
	"errors"
	"testing"
	"time"
)

func TestStoreCreatesSessionAndValidatesInput(t *testing.T) {
	store := NewStore()
	_, _, err := store.Create("", "Ada", "fibonacci")
	if err == nil {
		t.Fatal("Create accepted an empty session name")
	}
	session, token, err := store.Create("Sprint 12", " Ada ", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}
	if session.Name != "Sprint 12" || session.Members[0].Name != "Ada" || token == "" {
		t.Fatalf("session = %#v, token = %q", session, token)
	}
	if _, _, err := store.Create("valid", "Ada", "invalid"); err == nil {
		t.Fatal("Create accepted an unknown card type")
	}
}

func TestStoreVotingLifecycleAndConsensusDecision(t *testing.T) {
	store := NewStore()
	session, ownerToken, err := store.Create("Sprint", "Ada", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}
	_, bobToken, err := store.Join(session.ID, "Bob")
	if err != nil {
		t.Fatal(err)
	}
	session, err = store.AddVoting(session.ID, ownerToken, "Estimate login", "")
	if err != nil {
		t.Fatal(err)
	}
	voting := session.Votings[0]
	if _, err := store.StartRound(session.ID, ownerToken, voting.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Vote(session.ID, ownerToken, "5"); err != nil {
		t.Fatal(err)
	}
	session, err = store.Vote(session.ID, bobToken, "5")
	if err != nil {
		t.Fatal(err)
	}
	if session.Round != nil || session.Votings[0].Decision != "5" || len(session.Votings[0].Rounds) != 1 {
		t.Fatalf("round result = %#v", session)
	}
}

func TestStoreRejectsInvalidVotesAndRoundOperations(t *testing.T) {
	store := NewStore()
	session, token, err := store.Create("Sprint", "Ada", "t-shirt")
	if err != nil {
		t.Fatal(err)
	}
	session, err = store.AddVoting(session.ID, token, "Estimate", "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.Vote(session.ID, token, "S"); !errors.Is(err, ErrNoRound) {
		t.Fatalf("Vote() error = %v", err)
	}
	if _, err := store.StartRound(session.ID, token, session.Votings[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Vote(session.ID, token, "5"); err == nil {
		t.Fatal("Vote accepted a card outside the selected set")
	}
	if _, err := store.CancelRound(session.ID, token); err != nil {
		t.Fatal(err)
	}
}

func TestStoreTimeoutPersistsPartialRound(t *testing.T) {
	store := NewStore()
	now := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	store.now = func() time.Time { return now }
	session, ownerToken, err := store.Create("Sprint", "Ada", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = store.Join(session.ID, "Bob")
	if err != nil {
		t.Fatal(err)
	}
	session, err = store.AddVoting(session.ID, ownerToken, "Estimate", "")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.StartRound(session.ID, ownerToken, session.Votings[0].ID); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Vote(session.ID, ownerToken, "8"); err != nil {
		t.Fatal(err)
	}
	now = now.Add(31 * time.Second)
	store.ExpireRounds()
	session, _, err = store.Get(session.ID, ownerToken)
	if err != nil {
		t.Fatal(err)
	}
	if session.Round != nil || session.Votings[0].Rounds[0].Result != "timeout" {
		t.Fatalf("session = %#v", session)
	}
}

func TestStoreRequiresClosedSessionForDeletion(t *testing.T) {
	store := NewStore()
	session, token, err := store.Create("Sprint", "Ada", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}

	if err := store.Delete(session.ID, token); err == nil {
		t.Fatal("Delete succeeded for an open session")
	}
	if _, err := store.ToggleClosed(session.ID, token); err != nil {
		t.Fatal(err)
	}
	if err := store.Delete(session.ID, token); err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.Get(session.ID, token); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Get() error = %v", err)
	}
}

func TestSessionTokenCannotCrossPokerBoundaries(t *testing.T) {
	store := NewStore()
	first, firstToken, err := store.Create("First", "Ada", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}
	second, secondToken, err := store.Create("Second", "Ada", "fibonacci")
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.Get(second.ID, firstToken); !errors.Is(err, ErrUnauthorized) {
		t.Fatalf("cross-room Get() error = %v", err)
	}
	if _, err := store.ToggleClosed(first.ID, firstToken); err != nil {
		t.Fatal(err)
	}
	if err := store.Delete(first.ID, firstToken); err != nil {
		t.Fatal(err)
	}
	if _, _, err := store.Get(second.ID, secondToken); err != nil {
		t.Fatalf("second room token was invalidated: %v", err)
	}
}
