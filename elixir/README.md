# Phoenix reference implementation

This is the original Planning Poker implementation, retained as the behavioral reference while the Go/Svelte version is built.

From this directory:

```sh
mix setup
mix phx.server
```

The application is available at <http://localhost:4000>. Run the complete quality gate with:

```sh
mix precommit
```

The production Dockerfile and Fly configuration at the repository root now target the Go/Svelte implementation.
