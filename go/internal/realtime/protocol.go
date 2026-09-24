package realtime

import (
	"encoding/json"
	"errors"
	"fmt"
)

const ProtocolVersion = 1

var supportedTypes = map[string]struct{}{
	"connection.hello":              {},
	"connection.resume":             {},
	"connection.resumed":            {},
	"connection.resume_unavailable": {},
	"heartbeat.ping":                {},
	"heartbeat.pong":                {},
	"error":                         {},
}

type Envelope struct {
	Version int             `json:"v"`
	Type    string          `json:"type"`
	ID      string          `json:"id,omitempty"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type HelloPayload struct {
	ConnectionID    string `json:"connectionId"`
	ProtocolVersion int    `json:"protocolVersion"`
	HeartbeatMillis int64  `json:"heartbeatMillis"`
	ResumeSupported bool   `json:"resumeSupported"`
}

type HeartbeatPayload struct {
	Sequence uint64 `json:"sequence"`
}

type ResumePayload struct {
	Token        string `json:"token"`
	LastSequence uint64 `json:"lastSequence"`
}

type ErrorPayload struct {
	Code          string `json:"code"`
	Message       string `json:"message"`
	CorrelationID string `json:"correlationId,omitempty"`
}

func Decode(data []byte) (Envelope, error) {
	var envelope Envelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		return Envelope{}, errors.New("invalid JSON")
	}
	if envelope.Version != ProtocolVersion {
		return Envelope{}, fmt.Errorf("unsupported protocol version %d", envelope.Version)
	}
	if envelope.Type == "" {
		return Envelope{}, errors.New("message type is required")
	}
	if _, ok := supportedTypes[envelope.Type]; !ok {
		return Envelope{}, fmt.Errorf("unsupported message type %q", envelope.Type)
	}
	return envelope, nil
}

func NewEnvelope(messageType, id string, payload any) (Envelope, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return Envelope{}, err
	}
	return Envelope{Version: ProtocolVersion, Type: messageType, ID: id, Payload: data}, nil
}
