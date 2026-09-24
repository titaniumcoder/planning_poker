export interface Member {
  name: string;
  online: boolean;
  muted: boolean;
}

export interface FinishedRound {
  result: string;
  votes: Record<string, string>;
  participants: string[];
  endedAt: string;
}

export interface Voting {
  id: string;
  title: string;
  link?: string;
  decision?: string;
  position: number;
  rounds: FinishedRound[];
}

export interface ActiveRound {
  votingId: string;
  participants: string[];
  votes: Record<string, string>;
  endsAt: string;
}

export interface Poker {
  id: string;
  name: string;
  cardType: string;
  closedAt?: string;
  members: Member[];
  votings: Voting[];
  round?: ActiveRound;
}

export interface Snapshot {
  poker: Poker;
  user: Member;
  cards: string[];
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(path, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...options.headers },
    credentials: 'same-origin',
  });
  if (!response.ok) {
    const body = (await response.json().catch(() => ({ error: 'Request failed' }))) as {
      error: string;
    };
    throw new Error(body.error);
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export const createPoker = (body: object) =>
  request<Poker>('/api/v1/pokers', { method: 'POST', body: JSON.stringify(body) });
export const joinPoker = (id: string, body: object) =>
  request<Poker>(`/api/v1/pokers/${id}/join`, { method: 'POST', body: JSON.stringify(body) });
export const loadPoker = (id: string) => request<Snapshot>(`/api/v1/pokers/${id}`);
export const addVoting = (id: string, body: object) =>
  request<Poker>(`/api/v1/pokers/${id}/votings`, { method: 'POST', body: JSON.stringify(body) });
export const startRound = (id: string, votingId: string) =>
  request<Poker>(`/api/v1/pokers/${id}/round/start`, {
    method: 'POST',
    body: JSON.stringify({ votingId }),
  });
export const vote = (id: string, value: string) =>
  request<Poker>(`/api/v1/pokers/${id}/round/vote`, {
    method: 'POST',
    body: JSON.stringify({ vote: value }),
  });
export const cancelRound = (id: string) =>
  request<Poker>(`/api/v1/pokers/${id}/round/cancel`, { method: 'POST' });
export const toggleMute = (id: string) =>
  request<Poker>(`/api/v1/pokers/${id}/mute`, { method: 'POST' });
export const toggleSession = (id: string) =>
  request<Poker>(`/api/v1/pokers/${id}/session`, { method: 'POST' });
export const leavePoker = (id: string) =>
  request<void>(`/api/v1/pokers/${id}/leave`, { method: 'POST' });
