import {
  schema,
  table,
  t,
  SenderError,
  type InferSchema,
  type ReducerCtx,
} from 'spacetimedb/server';
import { ScheduleAt } from 'spacetimedb';

const room = table(
  { name: 'room', public: true },
  {
    code: t.string().primaryKey(),
    host: t.identity(),
    started: t.bool(),
    createdAt: t.timestamp(),
  }
);

// Slow-changing lobby data.
const player = table(
  { name: 'player', public: true },
  {
    identity: t.identity().primaryKey(),
    roomCode: t.string().index('btree'),
    name: t.string(),
    ready: t.bool(),
    online: t.bool(),
    joinedAt: t.timestamp(),
    // Appended last (with a default) so existing databases migrate without a reset.
    // Set while offline so the cleanup job can drop players who never come back.
    offlineSince: t.option(t.timestamp()).default(undefined),
  }
);

// Written ~20x/sec while playing, so kept apart from `player` to avoid flooding lobby subscribers.
const playerState = table(
  { name: 'player_state', public: true },
  {
    identity: t.identity().primaryKey(),
    roomCode: t.string().index('btree'),
    x: t.f32(),
    y: t.f32(),
    vx: t.f32(),
    vy: t.f32(),
    facing: t.i8(),
    updatedAt: t.timestamp(),
    // Cumulative impulses survive ordinary movement updates and batched subscriptions.
    impulseX: t.f64().default(0),
    impulseY: t.f64().default(0),
  }
);

const cleanupTimer = table(
  { name: 'cleanup_timer' },
  {
    scheduledId: t.u64().primaryKey().autoInc(),
    scheduledAt: t.scheduleAt(),
  }
);

const spacetimedb = schema({ room, player, playerState, cleanupTimer });
export default spacetimedb;

type Ctx = ReducerCtx<InferSchema<typeof spacetimedb>>;

// No I, L, or O so codes are easy to read aloud and type on a phone.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 4;
const MAX_PLAYERS = 8;
const MAX_NAME_LENGTH = 16;
// Spawn row sits on the 700px platform at (576, 500) in game/MHacks26_Game.tscn; keep in sync with the scene.
const SPAWN_X = 276;
const SPAWN_SPACING = 90;
const SPAWN_Y = 400;

const MICROS_PER_MINUTE = 60_000_000n;
const CLEANUP_INTERVAL_MICROS = 30_000_000n;
// A reload or a sleeping phone keeps its seat for this long.
const OFFLINE_GRACE_MICROS = 2n * MICROS_PER_MINUTE;
// Hard cap on room age, even if players are still connected.
const ROOM_MAX_AGE_MICROS = 30n * MICROS_PER_MINUTE;

function cleanName(raw: string): string {
  const name = raw.trim();
  if (name.length === 0 || name.length > MAX_NAME_LENGTH) {
    throw new SenderError(`Name must be 1-${MAX_NAME_LENGTH} characters`);
  }
  return name;
}

function generateCode(ctx: Ctx): string {
  for (let attempt = 0; attempt < 20; attempt++) {
    let code = '';
    for (let i = 0; i < CODE_LENGTH; i++) {
      code += CODE_ALPHABET[ctx.random.integerInRange(0, CODE_ALPHABET.length - 1)];
    }
    if (!ctx.db.room.code.find(code)) return code;
  }
  throw new SenderError('Could not allocate a room code, try again');
}

// Removes the player, then deletes the room if empty or hands host to the longest-present player.
function removePlayer(ctx: Ctx, identity: Ctx['sender']) {
  const existing = ctx.db.player.identity.find(identity);
  if (!existing) return;
  ctx.db.player.identity.delete(identity);
  ctx.db.playerState.identity.delete(identity);

  const room = ctx.db.room.code.find(existing.roomCode);
  if (!room) return;
  const remaining = [...ctx.db.player.roomCode.filter(existing.roomCode)];
  if (remaining.length === 0) {
    ctx.db.room.code.delete(room.code);
  } else if (room.host.equals(identity)) {
    remaining.sort((a, b) =>
      a.joinedAt.microsSinceUnixEpoch < b.joinedAt.microsSinceUnixEpoch ? -1 : 1
    );
    ctx.db.room.code.update({ ...room, host: remaining[0].identity });
  }
}

export const createRoom = spacetimedb.reducer(
  { name: t.string() },
  (ctx, { name }) => {
    const playerName = cleanName(name);
    removePlayer(ctx, ctx.sender);
    const code = generateCode(ctx);
    ctx.db.room.insert({
      code,
      host: ctx.sender,
      started: false,
      createdAt: ctx.timestamp,
    });
    ctx.db.player.insert({
      identity: ctx.sender,
      roomCode: code,
      name: playerName,
      ready: false,
      online: true,
      offlineSince: undefined,
      joinedAt: ctx.timestamp,
    });
  }
);

// Also serves as reconnect: an existing player in the same room is restored even after the game started.
export const joinRoom = spacetimedb.reducer(
  { code: t.string(), name: t.string() },
  (ctx, { code, name }) => {
    const playerName = cleanName(name);
    const roomCode = code.trim().toUpperCase();
    const room = ctx.db.room.code.find(roomCode);
    if (!room) throw new SenderError('Room not found');

    const existing = ctx.db.player.identity.find(ctx.sender);
    if (existing && existing.roomCode === roomCode) {
      ctx.db.player.identity.update({
        ...existing,
        name: playerName,
        online: true,
        offlineSince: undefined,
      });
      return;
    }

    if (room.started) throw new SenderError('Game already started');
    if ([...ctx.db.player.roomCode.filter(roomCode)].length >= MAX_PLAYERS) {
      throw new SenderError('Room is full');
    }

    removePlayer(ctx, ctx.sender);
    ctx.db.player.insert({
      identity: ctx.sender,
      roomCode,
      name: playerName,
      ready: false,
      online: true,
      offlineSince: undefined,
      joinedAt: ctx.timestamp,
    });
  }
);

export const leaveRoom = spacetimedb.reducer(ctx => {
  removePlayer(ctx, ctx.sender);
});

export const setReady = spacetimedb.reducer(
  { ready: t.bool() },
  (ctx, { ready }) => {
    const me = ctx.db.player.identity.find(ctx.sender);
    if (!me) throw new SenderError('Not in a room');
    const room = ctx.db.room.code.find(me.roomCode);
    if (room && room.started) throw new SenderError('Game already started');
    ctx.db.player.identity.update({ ...me, ready });
  }
);

// Offline players are ignored so a dropped phone cannot block the start.
export const startGame = spacetimedb.reducer(ctx => {
  const me = ctx.db.player.identity.find(ctx.sender);
  if (!me) throw new SenderError('Not in a room');
  const room = ctx.db.room.code.find(me.roomCode);
  if (!room) throw new SenderError('Room not found');
  if (!room.host.equals(ctx.sender)) throw new SenderError('Only the host can start the game');
  if (room.started) throw new SenderError('Game already started');

  const players = [...ctx.db.player.roomCode.filter(room.code)];
  const waiting = players.filter(
    p => p.online && !p.ready && !p.identity.equals(room.host)
  );
  if (waiting.length > 0) {
    throw new SenderError(`Waiting for ${waiting.map(p => p.name).join(', ')}`);
  }
  ctx.db.room.code.update({ ...room, started: true });

  players.sort((a, b) =>
    a.joinedAt.microsSinceUnixEpoch < b.joinedAt.microsSinceUnixEpoch ? -1 : 1
  );
  players.forEach((p, i) => {
    ctx.db.playerState.insert({
      identity: p.identity,
      roomCode: room.code,
      x: SPAWN_X + i * SPAWN_SPACING,
      y: SPAWN_Y,
      vx: 0,
      vy: 0,
      facing: 1,
      updatedAt: ctx.timestamp,
      impulseX: 0,
      impulseY: 0,
    });
  });
});

// Each client simulates its own player and publishes it here; others interpolate.
export const updateState = spacetimedb.reducer(
  { x: t.f32(), y: t.f32(), vx: t.f32(), vy: t.f32(), facing: t.i8() },
  (ctx, { x, y, vx, vy, facing }) => {
    const state = ctx.db.playerState.identity.find(ctx.sender);
    if (!state) throw new SenderError('Not in a started game');
    if (![x, y, vx, vy].every(Number.isFinite)) throw new SenderError('Invalid state');
    ctx.db.playerState.identity.update({
      ...state,
      x,
      y,
      vx,
      vy,
      facing: facing < 0 ? -1 : 1,
      updatedAt: ctx.timestamp,
    });
  }
);

// Called once when the grappling player reaches their target.
export const grappleHit = spacetimedb.reducer(
  { target: t.identity(), vx: t.f32(), vy: t.f32() },
  (ctx, { target, vx, vy }) => {
    if (target.equals(ctx.sender)) throw new SenderError('Cannot grapple yourself');
    if (![vx, vy].every(Number.isFinite)) throw new SenderError('Invalid impulse');

    const from = ctx.db.player.identity.find(ctx.sender);
    const to = ctx.db.player.identity.find(target);
    if (!from || !to || !from.online || !to.online || from.roomCode !== to.roomCode) {
      throw new SenderError('Target is not in your room');
    }
    const sourceState = ctx.db.playerState.identity.find(ctx.sender);
    const targetState = ctx.db.playerState.identity.find(target);
    if (!sourceState || !targetState || sourceState.roomCode !== from.roomCode ||
        targetState.roomCode !== from.roomCode) {
      throw new SenderError('Not in the same started game');
    }

    ctx.db.playerState.identity.update({
      ...targetState,
      impulseX: targetState.impulseX + vx,
      impulseY: targetState.impulseY + vy,
    });
  }
);

export const onConnect = spacetimedb.clientConnected(ctx => {
  ensureCleanupTimer(ctx);
  const existing = ctx.db.player.identity.find(ctx.sender);
  if (existing && !existing.online) {
    ctx.db.player.identity.update({ ...existing, online: true, offlineSince: undefined });
  }
});

// Only marks the player offline: a reload briefly overlaps old and new connections, and removal would drop them.
export const onDisconnect = spacetimedb.clientDisconnected(ctx => {
  const existing = ctx.db.player.identity.find(ctx.sender);
  if (existing && existing.online) {
    ctx.db.player.identity.update({ ...existing, online: false, offlineSince: ctx.timestamp });
  }
});

// `init` only runs on the first publish, so connections also make sure the repeating timer exists.
function ensureCleanupTimer(ctx: Ctx) {
  if (ctx.db.cleanupTimer.count() === 0n) {
    ctx.db.cleanupTimer.insert({
      scheduledId: 0n,
      scheduledAt: ScheduleAt.interval(CLEANUP_INTERVAL_MICROS),
    });
  }
}

export const init = spacetimedb.init(ctx => {
  ensureCleanupTimer(ctx);
});

// Removing players goes through removePlayer, which also hands off the host and deletes empty rooms.
export const cleanup = spacetimedb.reducer(
  { onSchedule: cleanupTimer },
  { timer: cleanupTimer.rowType },
  ctx => {
    const now = ctx.timestamp.microsSinceUnixEpoch;

    for (const room of [...ctx.db.room.iter()]) {
      if (now - room.createdAt.microsSinceUnixEpoch > ROOM_MAX_AGE_MICROS) {
        for (const p of [...ctx.db.player.roomCode.filter(room.code)]) {
          removePlayer(ctx, p.identity);
        }
        ctx.db.room.code.delete(room.code);
      }
    }

    for (const p of [...ctx.db.player.iter()]) {
      if (p.offlineSince && now - p.offlineSince.microsSinceUnixEpoch > OFFLINE_GRACE_MICROS) {
        removePlayer(ctx, p.identity);
      }
    }

    for (const room of [...ctx.db.room.iter()]) {
      if ([...ctx.db.player.roomCode.filter(room.code)].length === 0) {
        ctx.db.room.code.delete(room.code);
      }
    }
  }
);
