# Go and Svelte implementation guidance

## Backend

- Keep `cmd/server` as composition only; application logic belongs under `internal/`.
- Prefer the standard library. Add dependencies only when they materially improve correctness or security.
- Parse configuration once at startup and fail explicitly on invalid production values.
- Propagate contexts, bound all I/O, and implement graceful shutdown.
- WebSocket handlers must use exact origin validation, deadlines, read limits, bounded traffic, safe close codes, and a single controlled reader/writer flow.
- Never trust forwarded headers without an explicit trusted-proxy policy.
- Use structured logs without payloads or secrets.

## Protocol

- Every envelope includes protocol version and a known message type.
- Validate JSON and payload shapes before dispatch.
- Compatibility changes require an intentional versioning decision.
- Resume support must not claim successful restoration until state actually exists.

## Frontend

- Keep transport logic outside Svelte components.
- Validate all server messages at runtime.
- Clean up sockets, event listeners, and timers during disposal and HMR.
- Reconnect with capped jitter, respect offline/visibility state, and never persist secrets in local storage.
- Maintain accessible status announcements, focus styles, responsive behavior, and reduced-motion support.
- Do not add runtime CDN dependencies.

## Commands

- Backend dev: `go -C go tool air`
- Backend test: `go -C go test ./cmd/... ./internal/...`
- Backend lint: `go -C go tool golangci-lint run ./cmd/... ./internal/...`
- Frontend dev: `npm --prefix go/web run dev`
- Frontend check: `npm --prefix go/web run format:check && npm --prefix go/web run check && npm --prefix go/web run lint && npm --prefix go/web test`
- Production composition: `docker build -t planning-poker:local .`
