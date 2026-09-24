# Planning Poker

Planning Poker is being rebuilt as a Go backend with a Svelte frontend. The original Phoenix application remains under [`elixir/`](elixir/) as the behavioral reference.

## Repository layout

| Path | Purpose |
|---|---|
| `go/` | Active Go HTTP and realtime server |
| `go/web/` | Svelte 5 + TypeScript frontend |
| `elixir/` | Original Phoenix reference implementation |
| `Dockerfile` | The single production build, producing one Go application binary |
| `fly.toml` | Fly.io runtime and health configuration |

The Go service embeds the production Svelte assets. Production serves the page, API, and WebSocket from one origin and one process.

## Prerequisites

- Go 1.26.6
- Node.js 24.18.0 and npm
- Elixir 1.20.3 / Erlang OTP 28 only when working on the reference app
- Docker for production-image validation

The versions are recorded in `.tool-versions`.

## Local development

Use two terminals. These commands are identical in PowerShell, cmd, macOS shells, and Linux shells.

**Terminal 1 — Go with Air live reload**

```sh
go -C go tool air
```

**Terminal 2 — Svelte with Vite HMR**

```sh
npm install --prefix go/web
npm --prefix go/web run dev
```

Open <http://localhost:5173>. Vite proxies relative `/api` HTTP requests and `/api/v1/ws` WebSocket upgrades to Go on port `8080`. The browser therefore stays on one origin; no permissive CORS policy is needed. Go accepts the exact development WebSocket origin `http://localhost:5173`.

If `make` is installed, `make dev-go` and `make dev-web` provide the same two independent commands.

### Environment variables

| Variable | Default | Description |
|---|---|---|
| `APP_ENV` | `development` | Runtime environment; production applies stricter required configuration |
| `APP_ORIGIN` | `http://localhost:5173` | Exact browser origin allowed for WebSocket upgrades |
| `PORT` | `8080` | Go HTTP listen port |
| `WS_MAX_CONNECTIONS` | `500` | Global concurrent WebSocket limit |
| `WS_MESSAGES_PER_MINUTE` | `120` | Per-connection inbound message rate |
| `WS_MAX_MESSAGE_BYTES` | `16384` | Maximum WebSocket message size |

Air is pinned in `go.mod`, watches backend Go files only, and forwards shutdown signals before restart. Vite owns frontend HMR. Neither toolchain invokes the other.

## Quality commands

Backend:

```sh
gofmt -w go/cmd go/internal
go -C go vet ./cmd/... ./internal/...
go -C go tool golangci-lint run ./cmd/... ./internal/...
go -C go test ./cmd/... ./internal/...
go -C go tool govulncheck ./cmd/... ./internal/...
```

Frontend:

```sh
npm --prefix go/web run format:check
npm --prefix go/web run check
npm --prefix go/web run lint
npm --prefix go/web test
```

Phoenix reference:

```sh
cd elixir
mix precommit
```

## Production image

```sh
docker build -t planning-poker:local .
docker run --rm -p 8080:8080 -e APP_ENV=production -e APP_ORIGIN=http://localhost:8080 planning-poker:local
```

Then verify <http://localhost:8080/healthz>, <http://localhost:8080/readyz>, and <http://localhost:8080/>.

The Dockerfile keeps the toolchains independent: Node builds static files, the Go stage embeds that completed output, and the minimal runtime receives only the non-root Go application binary.

## Realtime foundation

`/api/v1/ws` provides a versioned JSON protocol with connection hello, heartbeat, explicit errors, and resume hooks. Resume currently returns `connection.resume_unavailable` because domain/session state is intentionally not part of this setup phase. Both server and browser enforce bounded messages, lifecycle cleanup, and safe reconnect behavior.

## Deployment

CI runs quality and image checks on branches and pull requests. The Fly deployment job can access credentials and run only for an exact push to `main`. Feature branches, including this setup branch, cannot deploy.
