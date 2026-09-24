# Planning Poker frontend

This is the Svelte 5 and TypeScript frontend for the Go implementation.

```sh
npm install
npm run dev
```

Vite serves the browser on <http://localhost:5173> and proxies `/api` HTTP and WebSocket traffic to the Go server on port `8080`. Use relative API URLs so local development and production remain same-origin.

Quality checks:

```sh
npm run format:check
npm run check
npm run lint
npm test
```

`npm run build` writes production assets to `../internal/web/dist`. The root Dockerfile copies that output into the Go build stage, where it is embedded into the application binary.
