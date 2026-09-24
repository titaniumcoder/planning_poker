# Realtime protocol

The WebSocket endpoint is `/api/v1/ws`. Messages are UTF-8 JSON envelopes:

```json
{
  "v": 1,
  "type": "heartbeat.pong",
  "id": "optional-correlation-id",
  "payload": {}
}
```

Version 1 defines:

| Direction | Type | Purpose |
|---|---|---|
| Server → client | `connection.hello` | Announces connection ID, protocol version, heartbeat interval, and resume capability |
| Server → client | `heartbeat.ping` | Liveness probe with a monotonic sequence |
| Client → server | `heartbeat.pong` | Mirrors the heartbeat sequence |
| Client → server | `connection.resume` | Supplies an opaque token and last acknowledged sequence |
| Server → client | `connection.resume_unavailable` | Explicitly reports that state restoration is not implemented yet |
| Server → client | `error` | Stable safe error code, message, and optional correlation ID |

Unknown versions/types, malformed payloads, binary messages, oversized messages, and rate violations are rejected. New domain messages must add typed Go and TypeScript payloads, runtime validation, integration tests, and an explicit compatibility decision.

Production accepts only the configured `APP_ORIGIN`. Local Vite development uses the exact `http://localhost:5173` origin and proxies the upgrade to Go; origin checks are never disabled.
