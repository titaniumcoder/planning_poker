import { describe, expect, it } from 'vitest';
import { isHeartbeatPayload, isHelloPayload, parseEnvelope } from './protocol';

describe('realtime protocol', () => {
  it('parses a supported envelope', () => {
    expect(parseEnvelope('{"v":1,"type":"heartbeat.ping","payload":{"sequence":2}}')).toEqual({
      v: 1,
      type: 'heartbeat.ping',
      payload: { sequence: 2 },
    });
  });

  it.each(['not-json', '{"v":2,"type":"heartbeat.ping"}', '{"v":1,"type":"unknown"}'])(
    'rejects invalid envelope %s',
    (value) => expect(() => parseEnvelope(value)).toThrow(),
  );

  it('validates typed payloads', () => {
    expect(
      isHelloPayload({
        connectionId: 'connection',
        protocolVersion: 1,
        heartbeatMillis: 20_000,
        resumeSupported: false,
      }),
    ).toBe(true);
    expect(isHeartbeatPayload({ sequence: 3 })).toBe(true);
    expect(isHeartbeatPayload({ sequence: -1 })).toBe(false);
  });
});
