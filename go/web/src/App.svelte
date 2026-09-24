<script lang="ts">
  import { onMount } from 'svelte';
  import { RealtimeClient } from './lib/realtime/client';

  const realtime = new RealtimeClient();
  const connection = realtime.state;

  const labels = {
    idle: 'Idle',
    connecting: 'Connecting',
    connected: 'Connected',
    reconnecting: 'Reconnecting',
    offline: 'Offline',
    failed: 'Connection issue',
  };

  onMount(() => {
    realtime.start();
    return () => realtime.stop();
  });
</script>

<svelte:head>
  <title>Planning Poker · Go + Svelte</title>
  <meta
    name="description"
    content="A realtime planning poker playground powered by Go and Svelte."
  />
</svelte:head>

<main>
  <nav aria-label="Primary navigation">
    <a class="brand" href="/" aria-label="Planning Poker home">
      <span class="brand-mark" aria-hidden="true">P</span>
      <span>Planning Poker</span>
    </a>
    <div
      class:connected={$connection.phase === 'connected'}
      class="connection-pill"
      role="status"
      aria-live="polite"
    >
      <span class="status-dot" aria-hidden="true"></span>
      <span data-testid="connection-status">{labels[$connection.phase]}</span>
    </div>
  </nav>

  <section class="hero" aria-labelledby="hero-title">
    <div class="eyebrow"><span></span> Go + Svelte foundation</div>
    <h1 id="hero-title">Planning poker, <em>rebuilt for speed.</em></h1>
    <p class="lede">
      The new realtime foundation is online. Secure WebSockets, graceful reconnects, and a
      single-binary deployment are ready for the game to arrive.
    </p>

    <div class="proof-grid">
      <article>
        <span class="proof-index">01</span>
        <h2>Realtime first</h2>
        <p>A typed, versioned connection with heartbeat monitoring and safe reconnects.</p>
      </article>
      <article>
        <span class="proof-index">02</span>
        <h2>One artifact</h2>
        <p>Svelte compiles into the Go binary for a small, predictable production image.</p>
      </article>
      <article>
        <span class="proof-index">03</span>
        <h2>Built to iterate</h2>
        <p>Air restarts the backend while Vite keeps frontend feedback instant.</p>
      </article>
    </div>
  </section>

  <footer>
    <span>Foundation phase</span>
    <span aria-hidden="true">·</span>
    <span>Domain features coming next</span>
  </footer>
</main>
