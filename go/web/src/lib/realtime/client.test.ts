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
}

describe('RealtimeClient', () => {
  let socket: FakeSocket;

  beforeEach(() => {
    vi.useFakeTimers();
    socket = new FakeSocket();
    sessionStorage.clear();
  });

  it('connects after a valid hello and answers heartbeats', () => {
    const client = new RealtimeClient({
      socketFactory: () => socket as unknown as WebSocket,
      random: () => 0.5,
    });

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
    const client = new RealtimeClient({
      socketFactory: () => socket as unknown as WebSocket,
    });
    client.start();

    socket.message({ v: 9, type: 'connection.hello' });

    expect(get(client.state).phase).toBe('failed');
    expect(socket.close).toHaveBeenCalledWith(1008, 'invalid server message');
    client.stop();
  });
});
