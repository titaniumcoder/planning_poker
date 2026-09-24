import { writable, type Readable } from 'svelte/store';
import {
  isHeartbeatPayload,
  isHelloPayload,
  parseEnvelope,
  protocolVersion,
  type Envelope,
} from './protocol';

export type ConnectionPhase =
  'idle' | 'connecting' | 'connected' | 'reconnecting' | 'offline' | 'failed';

export interface ConnectionState {
  phase: ConnectionPhase;
  attempts: number;
  detail?: string;
}

interface ResumeState {
  token: string;
  lastSequence: number;
}

interface ClientOptions {
  socketFactory?: (url: string) => WebSocket;
  random?: () => number;
  storage?: Storage;
  window?: Window;
}

const resumeKey = 'planning-poker.realtime.resume';

export class RealtimeClient {
  readonly state: Readable<ConnectionState>;

  private readonly setState: (state: ConnectionState) => void;
  private readonly socketFactory: (url: string) => WebSocket;
  private readonly random: () => number;
  private readonly storage: Storage;
  private readonly browser: Window;
  private socket?: WebSocket;
  private reconnectTimer?: number;
  private staleTimer?: number;
  private heartbeatMillis?: number;
  private stopped = true;
  private attempts = 0;

  constructor(options: ClientOptions = {}) {
    const store = writable<ConnectionState>({ phase: 'idle', attempts: 0 });
    this.state = { subscribe: store.subscribe };
    this.setState = store.set;
    this.socketFactory = options.socketFactory ?? ((url) => new WebSocket(url));
    this.random = options.random ?? Math.random;
    this.browser = options.window ?? window;
    this.storage = options.storage ?? this.browser.sessionStorage;
  }

  start(): void {
    if (!this.stopped) return;
    this.stopped = false;
    this.browser.addEventListener('online', this.handleOnline);
    this.browser.addEventListener('offline', this.handleOffline);
    this.browser.document.addEventListener('visibilitychange', this.handleVisibility);
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    this.clearTimers();
    this.browser.removeEventListener('online', this.handleOnline);
    this.browser.removeEventListener('offline', this.handleOffline);
    this.browser.document.removeEventListener('visibilitychange', this.handleVisibility);
    this.socket?.close(1000, 'client stopped');
    this.socket = undefined;
    this.setState({ phase: 'idle', attempts: 0 });
  }

  private connect(): void {
    if (this.stopped) return;
    if (!this.browser.navigator.onLine) {
      this.setState({ phase: 'offline', attempts: this.attempts });
      return;
    }

    this.setState({
      phase: this.attempts === 0 ? 'connecting' : 'reconnecting',
      attempts: this.attempts,
    });
    const scheme = this.browser.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const socket = this.socketFactory(`${scheme}//${this.browser.location.host}/api/v1/ws`);
    this.socket = socket;

    socket.addEventListener('message', this.handleMessage);
    socket.addEventListener('close', this.handleClose);
    socket.addEventListener('error', this.handleError);
  }

  private handleMessage = (event: MessageEvent<string>): void => {
    try {
      const envelope = parseEnvelope(event.data);
      switch (envelope.type) {
        case 'connection.hello':
          if (!isHelloPayload(envelope.payload)) throw new Error('Invalid hello payload');
          this.attempts = 0;
          this.heartbeatMillis = envelope.payload.heartbeatMillis;
          this.setState({ phase: 'connected', attempts: 0 });
          this.armStaleTimer(envelope.payload.heartbeatMillis);
          this.sendResume();
          break;
        case 'heartbeat.ping':
          if (!isHeartbeatPayload(envelope.payload)) throw new Error('Invalid heartbeat payload');
          if (this.heartbeatMillis) this.armStaleTimer(this.heartbeatMillis);
          this.persistSequence(envelope.payload.sequence);
          this.send({ v: protocolVersion, type: 'heartbeat.pong', payload: envelope.payload });
          break;
        case 'connection.resume_unavailable':
          this.storage.removeItem(resumeKey);
          break;
        case 'error':
          this.setState({
            phase: 'failed',
            attempts: this.attempts,
            detail: 'The realtime connection reported a protocol error.',
          });
          break;
      }
    } catch {
      this.setState({
        phase: 'failed',
        attempts: this.attempts,
        detail: 'The realtime connection sent an invalid message.',
      });
      this.socket?.close(1008, 'invalid server message');
    }
  };

  private handleClose = (): void => {
    this.clearStaleTimer();
    this.socket = undefined;
    if (!this.stopped) this.scheduleReconnect();
  };

  private handleError = (): void => {
    this.socket?.close();
  };

  private scheduleReconnect(): void {
    if (!this.browser.navigator.onLine) {
      this.setState({ phase: 'offline', attempts: this.attempts });
      return;
    }
    this.attempts++;
    const base = Math.min(30_000, 1_000 * 2 ** Math.min(this.attempts - 1, 5));
    const delay = Math.round(base * (0.75 + this.random() * 0.5));
    this.setState({ phase: 'reconnecting', attempts: this.attempts });
    this.reconnectTimer = this.browser.setTimeout(() => this.connect(), delay);
  }

  private armStaleTimer(heartbeatMillis: number): void {
    this.clearStaleTimer();
    this.staleTimer = this.browser.setTimeout(() => {
      this.socket?.close(1001, 'heartbeat timeout');
    }, heartbeatMillis * 2.5);
  }

  private sendResume(): void {
    const resume = this.readResume();
    if (!resume) return;
    this.send({
      v: protocolVersion,
      type: 'connection.resume',
      id: crypto.randomUUID(),
      payload: resume,
    });
  }

  private send(envelope: Envelope): void {
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.send(JSON.stringify(envelope));
    }
  }

  private persistSequence(sequence: number): void {
    const resume = this.readResume();
    if (resume) {
      this.storage.setItem(resumeKey, JSON.stringify({ ...resume, lastSequence: sequence }));
    }
  }

  private readResume(): ResumeState | undefined {
    const value = this.storage.getItem(resumeKey);
    if (!value) return undefined;
    try {
      const parsed = JSON.parse(value) as Partial<ResumeState>;
      if (typeof parsed.token === 'string' && Number.isSafeInteger(parsed.lastSequence)) {
        return { token: parsed.token, lastSequence: parsed.lastSequence ?? 0 };
      }
    } catch {
      // Cleared below.
    }
    this.storage.removeItem(resumeKey);
    return undefined;
  }

  private handleOnline = (): void => {
    if (!this.socket && !this.stopped) {
      this.attempts = 0;
      this.connect();
    }
  };

  private handleOffline = (): void => {
    this.clearTimers();
    this.socket?.close(1001, 'browser offline');
    this.setState({ phase: 'offline', attempts: this.attempts });
  };

  private handleVisibility = (): void => {
    if (this.browser.document.visibilityState === 'visible' && !this.socket && !this.stopped) {
      this.clearReconnectTimer();
      this.connect();
    }
  };

  private clearTimers(): void {
    this.clearReconnectTimer();
    this.clearStaleTimer();
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimer !== undefined) this.browser.clearTimeout(this.reconnectTimer);
    this.reconnectTimer = undefined;
  }

  private clearStaleTimer(): void {
    if (this.staleTimer !== undefined) this.browser.clearTimeout(this.staleTimer);
    this.staleTimer = undefined;
  }
}
