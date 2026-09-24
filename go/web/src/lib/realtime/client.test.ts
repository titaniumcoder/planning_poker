import { get } from 'svelte/store';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RealtimeClient } from './client';

class FakeSocket extends EventTarget {
  static readonly OPEN = 1;
  readonly sent: string[] = [];
  readyState = FakeSocket.OPEN;
  close = vi.fn();

  send(value: string): void {
    this.sent.push(value);
  }

  message(value: unknown): void {
    this.dispatchEvent(new MessageEvent('message', { data: JSON.stringify(value) }));
  }

  closeFromServer(): void {
    this.dispatchEvent(new CloseEvent('close'));
  }
}

describe('RealtimeClient', () => {
  let socket: FakeSocket;
  let browser: Window;

  beforeEach(() => {
    vi.useFakeTimers();
    socket = new FakeSocket();
    sessionStorage.clear();
    const document = new EventTarget() as Document;
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' });
    browser = Object.assign(new EventTarget(), {
      navigator: { onLine: true },
      location: { protocol: 'http:', host: 'example.test' },
      document,
      sessionStorage,
      setTimeout,
      clearTimeout,
    }) as unknown as Window;
  });

  function createClient(overrides: Partial<ConstructorParameters<typeof RealtimeClient>[0]> = {}) {
    return new RealtimeClient({
      socketFactory: () => socket as unknown as WebSocket,
      random: () => 0.5,
      window: browser,
      ...overrides,
    });
  }

  it('connects after a valid hello and answers heartbeats', () => {
    const client = createClient();

    client.start();
    expect(get(client.state).phase).toBe('connecting');

    socket.message({
      v: 1,
      type: 'connection.hello',
      payload: {
        connectionId: 'abc',
        protocolVersion: 1,
        heartbeatMillis: 20_000,
        resumeSupported: false,
      },
    });
    expect(get(client.state).phase).toBe('connected');

    socket.message({ v: 1, type: 'heartbeat.ping', payload: { sequence: 4 } });
    expect(JSON.parse(socket.sent.at(-1) ?? '{}')).toMatchObject({
      type: 'heartbeat.pong',
      payload: { sequence: 4 },
    });
    vi.advanceTimersByTime(40_000);
    expect(socket.close).not.toHaveBeenCalledWith(1001, 'heartbeat timeout');
    vi.advanceTimersByTime(11_000);
    expect(socket.close).toHaveBeenCalledWith(1001, 'heartbeat timeout');
    client.stop();
  });

  it('fails closed on invalid server messages', () => {
    const client = createClient();
    client.start();

    socket.message({ v: 9, type: 'connection.hello' });

    expect(get(client.state).phase).toBe('failed');
    expect(socket.close).toHaveBeenCalledWith(1008, 'invalid server message');
    client.stop();
  });

  it('is idempotent and cleans up listeners, timers, and sockets on stop', () => {
    const client = createClient();
    const add = vi.spyOn(browser, 'addEventListener');
    const remove = vi.spyOn(browser, 'removeEventListener');

    client.start();
    client.start();
    client.stop();
    expect(socket.close).toHaveBeenCalledWith(1000, 'client stopped');
    client.stop();

    expect(add).toHaveBeenCalledTimes(2);
    expect(remove).toHaveBeenCalledTimes(4);
    expect(get(client.state)).toEqual({ phase: 'idle', attempts: 0 });
    vi.runAllTimers();
    expect(get(client.state).phase).toBe('idle');
  });

  it('uses exponential jittered reconnects after an unexpected close', () => {
    const factory = vi.fn(() => socket as unknown as WebSocket);
    const client = createClient({ socketFactory: factory, random: () => 0 });
    client.start();
    socket.closeFromServer();

    expect(get(client.state)).toMatchObject({ phase: 'reconnecting', attempts: 1 });
    vi.advanceTimersByTime(750);
    expect(factory).toHaveBeenCalledTimes(2);
  });

  it('goes offline without reconnecting and resumes when the browser comes online', () => {
    const factory = vi.fn(() => socket as unknown as WebSocket);
    const client = createClient({ socketFactory: factory });
    client.start();

    Object.defineProperty(browser.navigator, 'onLine', { configurable: true, value: false });
    browser.dispatchEvent(new Event('offline'));
    socket.closeFromServer();
    expect(get(client.state)).toMatchObject({ phase: 'offline' });
    expect(socket.close).toHaveBeenCalledWith(1001, 'browser offline');

    Object.defineProperty(browser.navigator, 'onLine', { configurable: true, value: true });
    browser.dispatchEvent(new Event('online'));
    expect(factory).toHaveBeenCalledTimes(2);
    expect(get(client.state).phase).toBe('connecting');
  });

  it('persists heartbeat sequence and sends a stored resume request', () => {
    const storage = sessionStorage;
    storage.setItem(
      'planning-poker.realtime.resume',
      JSON.stringify({ token: 'resume-token', lastSequence: 3 }),
    );
    const client = createClient({ storage });
    client.start();
    socket.message({
      v: 1,
      type: 'connection.hello',
      payload: {
        connectionId: 'abc',
        protocolVersion: 1,
        heartbeatMillis: 1000,
        resumeSupported: true,
      },
    });

    const resume = JSON.parse(socket.sent[0] ?? '{}');
    expect(resume).toMatchObject({
      type: 'connection.resume',
      payload: { token: 'resume-token', lastSequence: 3 },
    });
    socket.message({ v: 1, type: 'heartbeat.ping', payload: { sequence: 4 } });
    expect(JSON.parse(storage.getItem('planning-poker.realtime.resume') ?? '{}')).toMatchObject({
      token: 'resume-token',
      lastSequence: 4,
    });
  });

  it('clears malformed and unavailable resume storage', () => {
    sessionStorage.setItem('planning-poker.realtime.resume', '{bad');
    const client = createClient();
    client.start();
    socket.message({
      v: 1,
      type: 'connection.hello',
      payload: {
        connectionId: 'abc',
        protocolVersion: 1,
        heartbeatMillis: 1000,
        resumeSupported: true,
      },
    });
    expect(sessionStorage.getItem('planning-poker.realtime.resume')).toBeNull();

    sessionStorage.setItem(
      'planning-poker.realtime.resume',
      JSON.stringify({ token: 'token', lastSequence: 1 }),
    );
    socket.message({ v: 1, type: 'connection.resume_unavailable' });
    expect(sessionStorage.getItem('planning-poker.realtime.resume')).toBeNull();
  });

  it('reconnects when a hidden tab becomes visible', () => {
    const factory = vi.fn(() => socket as unknown as WebSocket);
    const client = createClient({ socketFactory: factory });
    client.start();
    socket.closeFromServer();
    Object.defineProperty(browser.document, 'visibilityState', {
      configurable: true,
      value: 'visible',
    });
    browser.document.dispatchEvent(new Event('visibilitychange'));
    expect(factory).toHaveBeenCalledTimes(2);
  });
});
