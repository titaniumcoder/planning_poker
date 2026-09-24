// Package parity records the backend contract that must be ported from Phoenix.
//
// These tests are intentionally skipped while the Go service has no database or
// domain/session/user/voting implementation. Keeping the scenarios here makes
// the approved parity scope executable documentation without pretending that
// an in-memory transport test is equivalent to durable application behavior.
package parity

import "testing"

func TestDomainParityScenarios(t *testing.T) {
	t.Skip("blocked: Go domain layer and database are not implemented")
}

func TestSessionParityScenarios(t *testing.T) {
	t.Skip("blocked: Go session lifecycle has not been implemented")
}

func TestUserParityScenarios(t *testing.T) {
	t.Skip("blocked: Go user tracking has not been implemented")
}

func TestVotingParityScenarios(t *testing.T) {
	t.Skip("blocked: Go voting state machine has not been implemented")
}
