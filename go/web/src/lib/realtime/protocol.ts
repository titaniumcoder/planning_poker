export const protocolVersion = 1;

export type MessageType =
  | 'connection.hello'
  | 'connection.resume'
  | 'connection.resumed'
  | 'connection.resume_unavailable'
  | 'heartbeat.ping'
  | 'heartbeat.pong'
  | 'error';

export interface Envelope<T = unknown> {
  v: number;
  type: MessageType;
  id?: string;
  payload?: T;
}

export interface HelloPayload {
  connectionId: string;
  protocolVersion: number;
  heartbeatMillis: number;
  resumeSupported: boolean;
}

export interface HeartbeatPayload {
  sequence: number;
}

const messageTypes = new Set<MessageType>([
  'connection.hello',
  'connection.resume',
  'connection.resumed',
  'connection.resume_unavailable',
  'heartbeat.ping',
  'heartbeat.pong',
  'error',
]);

export function parseEnvelope(value: string): Envelope {
  const parsed: unknown = JSON.parse(value);
  if (!isRecord(parsed) || parsed.v !== protocolVersion || typeof parsed.type !== 'string') {
    throw new Error('Invalid realtime envelope');
  }
  if (!messageTypes.has(parsed.type as MessageType)) {
    throw new Error('Unsupported realtime message');
  }
  if (parsed.id !== undefined && typeof parsed.id !== 'string') {
    throw new Error('Invalid realtime message id');
  }
  return parsed as unknown as Envelope;
}

export function isHelloPayload(payload: unknown): payload is HelloPayload {
  return (
    isRecord(payload) &&
    typeof payload.connectionId === 'string' &&
    payload.protocolVersion === protocolVersion &&
    typeof payload.heartbeatMillis === 'number' &&
    payload.heartbeatMillis > 0 &&
    typeof payload.resumeSupported === 'boolean'
  );
}

export function isHeartbeatPayload(payload: unknown): payload is HeartbeatPayload {
  return (
    isRecord(payload) &&
    typeof payload.sequence === 'number' &&
    Number.isSafeInteger(payload.sequence) &&
    payload.sequence >= 0
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
