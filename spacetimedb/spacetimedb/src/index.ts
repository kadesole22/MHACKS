import {
  schema,
  table,
  t,
  SenderError,
  type InferSchema,
  type ReducerCtx,
} from 'spacetimedb/server';

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
  }
);

const spacetimedb = schema({ room, player, playerState });
export default spacetimedb;

type Ctx = ReducerCtx<InferSchema<typeof spacetimedb>>;

// No I, L, or O so codes are easy to read aloud and type on a phone.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 4;
const MAX_PLAYERS = 8;
const MAX_NAME_LENGTH = 16;

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
      ctx.db.player.identity.update({ ...existing, name: playerName, online: true });
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

  const waiting = [...ctx.db.player.roomCode.filter(room.code)].filter(
    p => p.online && !p.ready && !p.identity.equals(room.host)
  );
  if (waiting.length > 0) {
    throw new SenderError(`Waiting for ${waiting.map(p => p.name).join(', ')}`);
  }
  ctx.db.room.code.update({ ...room, started: true });
});

export const onConnect = spacetimedb.clientConnected(ctx => {
  const existing = ctx.db.player.identity.find(ctx.sender);
  if (existing && !existing.online) {
    ctx.db.player.identity.update({ ...existing, online: true });
  }
});

// Only marks the player offline: a reload briefly overlaps old and new connections, and removal would drop them.
export const onDisconnect = spacetimedb.clientDisconnected(ctx => {
  const existing = ctx.db.player.identity.find(ctx.sender);
  if (existing && existing.online) {
    ctx.db.player.identity.update({ ...existing, online: false });
  }
});
