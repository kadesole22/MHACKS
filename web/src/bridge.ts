import type { Identity } from 'spacetimedb';
import type { DbConnection } from './module_bindings';

// Methods return primitives or JSON strings because Godot's JavaScriptBridge cannot convert rich JS objects.
export interface StdbBridge {
  myId(): string;
  roomCode(): string;
  /** JSON array of { id, name, online, me, x, y, vx, vy, facing } for every player in my room. */
  players(): string;
  sendState(x: number, y: number, vx: number, vy: number, facing: number): void;
  sendGrappleHit(targetId: string, vx: number, vy: number): boolean;
  /** JSON [vx, vy] accumulated since the previous read, or null. */
  takeImpulse(): string;
}

declare global {
  interface Window {
    stdb?: StdbBridge;
  }
}

export function installBridge(conn: DbConnection, me: Identity): void {
  const roomCode = () => conn.db.player.identity.find(me)?.roomCode ?? '';
  let impulseBaseline: { room: string; x: number; y: number } | null = null;

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
    sendGrappleHit(targetId, vx, vy) {
      if (![vx, vy].every(Number.isFinite)) return false;
      for (const p of conn.db.player.iter()) {
        if (p.identity.toHexString() !== targetId || p.identity.isEqual(me) ||
            p.roomCode !== roomCode() || !p.online) continue;
        conn.reducers.grappleHit({ target: p.identity, vx, vy }).catch(error => {
          console.error('Grapple impact rejected:', error);
        });
        return true;
      }
      return false;
    },
    takeImpulse() {
      const s = conn.db.playerState.identity.find(me);
      if (!s || s.roomCode !== roomCode()) {
        impulseBaseline = null;
        return 'null';
      }
      const current = { room: s.roomCode, x: s.impulseX, y: s.impulseY };
      const previous = impulseBaseline;
      impulseBaseline = current;
      // Establish a baseline on entry/reconnect rather than replay old impacts.
      if (!previous || previous.room !== current.room) return 'null';
      const vx = current.x - previous.x;
      const vy = current.y - previous.y;
      return vx === 0 && vy === 0 ? 'null' : JSON.stringify([vx, vy]);
    },
  };
}
