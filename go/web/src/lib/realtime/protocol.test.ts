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

  it.each([
    '{"v":1,"type":"heartbeat.ping","id":42}',
    '{"v":1,"type":"heartbeat.ping","id":null}',
    '{"v":1,"type":"heartbeat.ping","payload":[]}',
    '{"v":1,"type":42}',
  ])('rejects malformed envelope fields: %s', (value) => {
    expect(() => parseEnvelope(value)).toThrow();
  });

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

  it.each([
    undefined,
    null,
    {},
    { connectionId: '', protocolVersion: 1, heartbeatMillis: 20_000, resumeSupported: true },
    {
      connectionId: 'connection',
      protocolVersion: 2,
      heartbeatMillis: 20_000,
      resumeSupported: true,
    },
    { connectionId: 'connection', protocolVersion: 1, heartbeatMillis: 0, resumeSupported: true },
    {
      connectionId: 'connection',
      protocolVersion: 1,
      heartbeatMillis: 20_000,
      resumeSupported: 'yes',
    },
  ])('rejects invalid hello payload %#', (payload) => {
    expect(isHelloPayload(payload)).toBe(false);
  });

  it.each([
    undefined,
    null,
    {},
    { sequence: 1.5 },
    { sequence: Number.MAX_SAFE_INTEGER + 1 },
    { sequence: -1 },
  ])('rejects invalid heartbeat payload %#', (payload) => {
    expect(isHeartbeatPayload(payload)).toBe(false);
  });
});
