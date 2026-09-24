import { expect, request, test, type APIRequestContext } from '@playwright/test';

const roomCount = Number(process.env.POKER_LOAD_ROOMS ?? 50);
const seed = Number(process.env.POKER_LOAD_SEED ?? 20260924);
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:8080';

interface Poker {
  id: string;
  cardType: string;
  round?: { votingId: string };
  votings: Array<{
    id: string;
    decision?: string;
    rounds: Array<{ result: string; votes: Record<string, string> }>;
  }>;
}

test.describe.configure({ mode: 'serial', timeout: Math.max(180_000, roomCount * 2_000) });

test(`runs ${roomCount} concurrent multi-user planning sessions`, async () => {
  const startedAt = Date.now();
  const results = await Promise.all(
    Array.from({ length: roomCount }, (_, roomIndex) => runRoom(roomIndex)),
  );

  const totalUsers = results.reduce((sum, result) => sum + result.users, 0);
  const totalRounds = results.reduce((sum, result) => sum + result.rounds, 0);
  const elapsedSeconds = (Date.now() - startedAt) / 1_000;

  console.log(
    JSON.stringify({
      rooms: roomCount,
      users: totalUsers,
      rounds: totalRounds,
      elapsedSeconds,
      roundsPerSecond: totalRounds / elapsedSeconds,
    }),
  );

  expect(totalUsers).toBeGreaterThanOrEqual(roomCount * 3);
  expect(totalUsers).toBeLessThanOrEqual(roomCount * 8);
  expect(totalRounds).toBeGreaterThanOrEqual(roomCount * 3);
  expect(totalRounds).toBeLessThanOrEqual(roomCount * 12);
});

async function runRoom(roomIndex: number): Promise<{ users: number; rounds: number }> {
  const random = mulberry32(seed + roomIndex);
  const userCount = integer(random, 3, 8);
  const roundCount = integer(random, 3, 12);
  const cardType = random() < 0.5 ? 'fibonacci' : 't-shirt';
  const cards =
    cardType === 'fibonacci' ? ['1', '2', '3', '5', '8', '13'] : ['XS', 'S', 'M', 'L', 'XL'];
  const users: APIRequestContext[] = [];

  try {
    const owner = await request.newContext({ baseURL });
    users.push(owner);
    const created = await post<Poker>(
      owner,
      '/api/v1/pokers',
      {
        name: `Load room ${roomIndex}`,
        username: `user-${roomIndex}-0`,
        cardType,
        privacyAccepted: true,
      },
      201,
    );

    const joiners = await Promise.all(
      Array.from({ length: userCount - 1 }, async (_, userIndex) => {
        await delay(integer(random, 5, 40));
        const client = await request.newContext({ baseURL });
        await post<Poker>(client, `/api/v1/pokers/${created.id}/join`, {
          username: `user-${roomIndex}-${userIndex + 1}`,
          privacyAccepted: true,
        });
        return client;
      }),
    );
    users.push(...joiners);

    let finalPoker = created;
    for (let roundIndex = 0; roundIndex < roundCount; roundIndex++) {
      await delay(integer(random, 10, 60));
      finalPoker = await post<Poker>(owner, `/api/v1/pokers/${created.id}/votings`, {
        title: `Story ${roundIndex + 1}`,
        link: `https://example.test/story/${roomIndex}/${roundIndex}`,
      });
      const voting = finalPoker.votings.at(-1);
      expect(voting).toBeDefined();

      finalPoker = await post<Poker>(owner, `/api/v1/pokers/${created.id}/round/start`, {
        votingId: voting!.id,
      });
      expect(finalPoker.round?.votingId).toBe(voting!.id);

      const selectedCard = cards[integer(random, 0, cards.length - 1)];
      const voteResponses = await Promise.all(
        users.map(async (client) => {
          await delay(integer(random, 5, 50));
          return post<Poker>(client, `/api/v1/pokers/${created.id}/round/vote`, {
            vote: selectedCard,
          });
        }),
      );
      finalPoker = voteResponses.find((poker) => !poker.round) ?? voteResponses.at(-1)!;
    }

    const snapshot = await get<{ poker: Poker }>(owner, `/api/v1/pokers/${created.id}`);
    expect(snapshot.poker.round).toBeUndefined();
    expect(snapshot.poker.votings).toHaveLength(roundCount);
    for (const voting of snapshot.poker.votings) {
      expect(voting.rounds).toHaveLength(1);
      expect(voting.rounds[0].result).toBe('completed');
      expect(Object.keys(voting.rounds[0].votes)).toHaveLength(userCount);
      expect(voting.decision).toBeTruthy();
    }
    return { users: userCount, rounds: roundCount };
  } finally {
    await Promise.all(users.map((client) => client.dispose()));
  }
}

async function post<T>(
  client: APIRequestContext,
  path: string,
  data?: object,
  expectedStatus = 200,
): Promise<T> {
  const response = await client.post(path, { data });
  const body = await response.text();
  expect(response.status(), `${path}: ${body}`).toBe(expectedStatus);
  return JSON.parse(body) as T;
}

async function get<T>(client: APIRequestContext, path: string): Promise<T> {
  const response = await client.get(path);
  const body = await response.text();
  expect(response.status(), `${path}: ${body}`).toBe(200);
  return JSON.parse(body) as T;
}

function integer(random: () => number, minimum: number, maximum: number): number {
  return Math.floor(random() * (maximum - minimum + 1)) + minimum;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function mulberry32(value: number): () => number {
  return () => {
    value |= 0;
    value = (value + 0x6d2b79f5) | 0;
    let result = Math.imul(value ^ (value >>> 15), 1 | value);
    result = (result + Math.imul(result ^ (result >>> 7), 61 | result)) ^ result;
    return ((result ^ (result >>> 14)) >>> 0) / 4_294_967_296;
  };
}
