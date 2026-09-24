<script lang="ts">
  import { onMount } from 'svelte';
  import {
    addVoting,
    cancelRound,
    createPoker,
    joinPoker,
    leavePoker,
    loadPoker,
    startRound,
    toggleMute,
    toggleSession,
    vote,
    type Poker,
    type Snapshot,
  } from './lib/poker-api';
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
  let poker: Poker | undefined;
  let user = '';
  let cards: string[] = [];
  let route = 'home';
  let sessionName = '';
  let username = '';
  let cardType = 'fibonacci';
  let privacyAccepted = false;
  let votingTitle = '';
  let votingLink = '';
  let error = '';
  let loading = false;

  function pokerID(): string | undefined {
    return /^\/poker\/([a-f0-9]+)$/i.exec(window.location.pathname)?.[1];
  }

  function showPoker(id: string): void {
    history.pushState({}, '', `/poker/${id}`);
    route = 'poker';
    void refresh();
  }

  async function refresh(): Promise<void> {
    const id = pokerID();
    if (!id) return;
    try {
      const snapshot: Snapshot = await loadPoker(id);
      poker = snapshot.poker;
      user = snapshot.user.name;
      cards = snapshot.cards;
      error = '';
    } catch (reason) {
      poker = undefined;
      error = reason instanceof Error ? reason.message : 'Could not load the session.';
    }
  }

  async function create(): Promise<void> {
    loading = true;
    try {
      const created = await createPoker({ name: sessionName, username, cardType, privacyAccepted });
      showPoker(created.id);
    } catch (reason) {
      error = reason instanceof Error ? reason.message : 'Could not create the session.';
    } finally {
      loading = false;
    }
  }

  async function join(): Promise<void> {
    const id = pokerID();
    if (!id) return;
    loading = true;
    try {
      await joinPoker(id, { username, privacyAccepted });
      await refresh();
    } catch (reason) {
      error = reason instanceof Error ? reason.message : 'Could not join the session.';
    } finally {
      loading = false;
    }
  }

  async function act(action: () => Promise<Poker>): Promise<void> {
    try {
      poker = await action();
      error = '';
    } catch (reason) {
      error = reason instanceof Error ? reason.message : 'Could not update the session.';
    }
  }

  onMount(() => {
    realtime.start();
    route = pokerID() ? 'poker' : 'home';
    if (route === 'poker') void refresh();
    const timer = window.setInterval(() => {
      if (route === 'poker' && poker) void refresh();
    }, 2_000);
    const onPopState = () => {
      route = pokerID() ? 'poker' : 'home';
      if (route === 'poker') void refresh();
    };
    window.addEventListener('popstate', onPopState);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener('popstate', onPopState);
      realtime.stop();
    };
  });
</script>

<svelte:head>
  <title>{poker ? `${poker.name} · Planning Poker` : 'Planning Poker'}</title>
  <meta name="description" content="A collaborative estimation tool for agile teams." />
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

  {#if error}
    <p class="alert" role="alert">{error}</p>
  {/if}

  {#if route === 'home'}
    <section class="hero" aria-labelledby="hero-title">
      <div class="eyebrow"><span></span> collaborative estimation</div>
      <h1 id="hero-title">Make the next estimate <em>together.</em></h1>
      <p class="lede">
        Create a private planning-poker room, invite your team, and reveal consensus in real time.
      </p>
      <form
        onsubmit={(event) => {
          event.preventDefault();
          void create();
        }}
        class="card"
        aria-label="Create session"
      >
        <h2>Start a new session</h2>
        <label>Session name <input bind:value={sessionName} maxlength="100" required /></label>
        <label>Your name <input bind:value={username} maxlength="100" required /></label>
        <label
          >Card set <select bind:value={cardType}
            ><option value="fibonacci">Fibonacci</option><option value="t-shirt">T-shirt</option
            ></select
          ></label
        >
        <label class="check"
          ><input type="checkbox" bind:checked={privacyAccepted} /> I agree to the privacy policy.</label
        >
        <button disabled={loading} type="submit">Create planning poker</button>
      </form>
    </section>
  {:else if !poker}
    <section class="hero">
      <h1>Join this session</h1>
      <p class="lede">Choose a name to participate in the estimate.</p>
      <form
        onsubmit={(event) => {
          event.preventDefault();
          void join();
        }}
        class="card"
        aria-label="Join session"
      >
        <label>Your name <input bind:value={username} maxlength="100" required /></label>
        <label class="check"
          ><input type="checkbox" bind:checked={privacyAccepted} /> I agree to the privacy policy.</label
        >
        <button disabled={loading} type="submit">Join session</button>
      </form>
    </section>
  {:else}
    <section class="hero room" aria-labelledby="room-title">
      <div class="eyebrow"><span></span>{poker.closedAt ? 'session closed' : 'session open'}</div>
      <h1 id="room-title">{poker.name}</h1>
      <p class="lede">
        Share this URL with your team. {poker.members.filter((member) => member.online).length} participants
        online.
      </p>
      <div class="room-actions">
        <button onclick={() => navigator.clipboard.writeText(window.location.href)}
          >Copy invite link</button
        >
        <button onclick={() => void act(() => toggleMute(poker!.id))}
          >{poker.members.find((member) => member.name === user)?.muted
            ? 'Unmute myself'
            : 'Mute myself'}</button
        >
        <button onclick={() => void act(() => toggleSession(poker!.id))}
          >{poker.closedAt ? 'Reopen' : 'Terminate'}</button
        >
        <button
          onclick={() =>
            void leavePoker(poker!.id).then(() => {
              history.pushState({}, '', '/');
              route = 'home';
              poker = undefined;
            })}>Leave</button
        >
      </div>

      <form
        onsubmit={(event) => {
          event.preventDefault();
          void act(() => addVoting(poker!.id, { title: votingTitle, link: votingLink }));
          votingTitle = '';
          votingLink = '';
        }}
        class="card"
        aria-label="Add voting"
      >
        <h2>Add a voting</h2>
        <label>Title <input bind:value={votingTitle} maxlength="200" required /></label>
        <label>Link <input bind:value={votingLink} type="url" maxlength="500" /></label>
        <button disabled={Boolean(poker.closedAt)} type="submit">Add voting</button>
      </form>

      <div class="proof-grid" aria-label="Voting items">
        {#each poker.votings as voting (voting.id)}
          <article>
            <span class="proof-index">#{voting.position}</span>
            <h2>{voting.title}</h2>
            {#if voting.link}<a href={voting.link} target="_blank" rel="noreferrer">Open item</a
              >{/if}
            {#if voting.decision}<p><strong>Decision:</strong> {voting.decision}</p>{/if}
            {#if poker.round?.votingId === voting.id}
              <p class="lede">
                Voting in progress: {Object.keys(poker.round.votes).length}/{poker.round
                  .participants.length} votes cast.
              </p>
              {#if poker.round.participants.includes(user)}
                <div class="cards">
                  {#each cards as card (card)}<button
                      class:connected={poker.round.votes[user] === card}
                      onclick={() => void act(() => vote(poker!.id, card))}>{card}</button
                    >{/each}
                </div>
              {/if}
              <button onclick={() => void act(() => cancelRound(poker!.id))}>Cancel voting</button>
            {:else}
              <button
                disabled={Boolean(poker.closedAt)}
                onclick={() => void act(() => startRound(poker!.id, voting.id))}
                >Start voting</button
              >
            {/if}
            {#if voting.rounds.length}
              <h3>Voting rounds</h3>
              {#each voting.rounds as round, index (round.endedAt)}<p>
                  Round {index + 1} ({round.result}): {Object.entries(round.votes)
                    .map(([name, card]) => `${name}: ${card}`)
                    .join(', ')}
                </p>{/each}
            {:else}<p>No voting rounds yet.</p>{/if}
          </article>
        {/each}
      </div>
    </section>
  {/if}

  <footer>
    <span>Planning Poker</span>
    <span aria-hidden="true">·</span>
    <span>Estimate together</span>
  </footer>
</main>
