.PHONY: dev-go dev-web test-go test-web check-go check-web build-image

dev-go:
	go -C go tool air

dev-web:
	npm --prefix go/web run dev

test-go:
	go -C go test ./cmd/... ./internal/...

test-web:
	npm --prefix go/web test

check-go:
	gofmt -l go/cmd go/internal
	go -C go vet ./cmd/... ./internal/...
	go -C go tool golangci-lint run ./cmd/... ./internal/...
	go -C go test ./cmd/... ./internal/...
	go -C go tool govulncheck ./cmd/... ./internal/...

check-web:
	npm --prefix go/web run format:check
	npm --prefix go/web run check
	npm --prefix go/web run lint
	npm --prefix go/web test

build-image:
	docker build --tag planning-poker:local .
