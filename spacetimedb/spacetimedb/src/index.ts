import { schema, table, t } from 'spacetimedb/server';

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
