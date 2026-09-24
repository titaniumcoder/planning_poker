# syntax=docker/dockerfile:1.7

FROM node:24.18.0-bookworm-slim AS web-builder
WORKDIR /src/go/web
COPY go/web/package.json go/web/package-lock.json ./
RUN npm ci
COPY go/web/ ./
RUN npm run check && npm run test && npm run build

FROM golang:1.26.6-bookworm AS go-builder
WORKDIR /src/go
COPY go/go.mod go/go.sum ./
RUN go mod download
COPY go/ ./
COPY --from=web-builder /src/go/internal/web/dist ./internal/web/dist
RUN go test ./cmd/... ./internal/... \
    && CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/planning-poker ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /app
COPY --from=go-builder --chown=nonroot:nonroot /out/planning-poker /app/planning-poker
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/planning-poker"]
