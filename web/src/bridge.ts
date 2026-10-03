import type { Identity } from 'spacetimedb';
import type { DbConnection } from './module_bindings';

// Methods return primitives or JSON strings because Godot's JavaScriptBridge cannot convert rich JS objects.
export interface StdbBridge {
  myId(): string;
  roomCode(): string;
  /** JSON array of { id, name, online, me, x, y, vx, vy, facing } for every player in my room. */
  players(): string;
  sendState(x: number, y: number, vx: number, vy: number, facing: number): void;
}

declare global {
  interface Window {
    stdb?: StdbBridge;
  }
}

export function installBridge(conn: DbConnection, me: Identity): void {
  const roomCode = () => conn.db.player.identity.find(me)?.roomCode ?? '';

  window.stdb = {
    myId: () => me.toHexString(),
    roomCode,
    players() {
      const code = roomCode();
      const out = [];
      for (const p of conn.db.player.iter()) {
        if (p.roomCode !== code) continue;
        const s = conn.db.playerState.identity.find(p.identity);
        if (!s) continue;
        out.push({
          id: p.identity.toHexString(),
          name: p.name,
          online: p.online,
          me: p.identity.isEqual(me),
          x: s.x,
          y: s.y,
          vx: s.vx,
          vy: s.vy,
          facing: s.facing,
        });
      }
      return JSON.stringify(out);
    },
    sendState(x, y, vx, vy, facing) {
      // Called ~20x/sec, so rejected calls (for example after leaving) are dropped silently.
      conn.reducers.updateState({ x, y, vx, vy, facing }).catch(() => {});
    },
  };
}
