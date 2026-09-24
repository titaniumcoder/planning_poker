# Planning Poker repository guidance

## Architecture

- `elixir/` is the Phoenix reference implementation. Preserve its behavior and follow `elixir/AGENTS.md`.
- `go/` is the active Go/Svelte replacement. Follow `go/AGENTS.md`.
- The repository must keep exactly one root `Dockerfile`.
- Production is one non-root Go application binary with the compiled Svelte assets embedded.
- The Go scaffold has no database or migration dependency.

## Toolchain boundaries

- Go commands run from `go/` or with `go -C go`.
- Frontend commands run from `go/web/` or with `npm --prefix go/web`.
- npm scripts must not invoke Go commands. Go tooling must not invoke npm.
- `make` targets are optional convenience wrappers. Direct commands documented in `README.md` are authoritative on every OS.
- Local development uses two terminals: repository-pinned Air for Go and Vite for Svelte.

## Required quality checks

- Go changes: format, vet, golangci-lint, tests, race tests where supported, and govulncheck.
- Frontend changes: Prettier, ESLint, svelte-check/TypeScript, Vitest, and relevant Playwright tests.
- Phoenix changes or repository moves: run `mix precommit` from `elixir/`.
- Deployment changes: build the root Docker image and verify health, readiness, SPA, and WebSocket behavior.

## Realtime and security invariants

- Keep the WebSocket protocol versioned and runtime-validated on both sides.
- Validate exact origins. Never add wildcard CORS or disable WebSocket origin checks.
- Keep message sizes, rates, queues, deadlines, and connection counts bounded.
- Preserve one reader/one writer ownership, cancellation, graceful close behavior, and leak tests.
- Never log message payloads, resume tokens, session secrets, or future poker secrets.
- Protocol changes require Go integration tests and TypeScript client tests.

## Deployment

- CI may build and test every branch.
- Fly credentials and deployment steps must remain inaccessible unless the event is an exact push to `main`.
- Never deploy from a feature branch.
