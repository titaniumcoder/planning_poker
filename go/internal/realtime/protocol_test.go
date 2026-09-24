package realtime

import "testing"

func TestDecode(t *testing.T) {
	envelope, err := Decode([]byte(`{"v":1,"type":"heartbeat.pong","payload":{"sequence":1}}`))
	if err != nil {
		t.Fatalf("Decode() error = %v", err)
	}
	if envelope.Type != "heartbeat.pong" {
		t.Fatalf("Type = %q", envelope.Type)
	}
}

func TestDecodeRejectsInvalidProtocol(t *testing.T) {
	tests := [][]byte{
		[]byte(`not-json`),
		[]byte(`{"v":2,"type":"heartbeat.pong"}`),
		[]byte(`{"v":1}`),
	}
	for _, input := range tests {
		if _, err := Decode(input); err == nil {
			t.Fatalf("Decode(%q) error = nil", input)
		}
	}
}

func TestDecodeRejectsUnknownMessageType(t *testing.T) {
	if _, err := Decode([]byte(`{"v":1,"type":"room.delete"}`)); err == nil {
		t.Fatal("Decode() error = nil, want unsupported message type error")
	}
}

func TestDecodeRejectsInvalidMessageID(t *testing.T) {
	if _, err := Decode([]byte(`{"v":1,"type":"heartbeat.pong","id":42}`)); err == nil {
		t.Fatal("Decode() error = nil, want invalid id error")
	}
}

func TestDecodeAcceptsVersionOneMessageTypes(t *testing.T) {
	for _, messageType := range []string{
		"connection.hello", "connection.resume", "connection.resume_unavailable",
		"heartbeat.ping", "heartbeat.pong", "error",
	} {
		t.Run(messageType, func(t *testing.T) {
			if _, err := Decode([]byte(`{"v":1,"type":"` + messageType + `"}`)); err != nil {
				t.Fatalf("Decode() error = %v", err)
			}
		})
	}
}
