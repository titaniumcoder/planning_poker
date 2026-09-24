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
