import './style.css';
import type { Identity } from 'spacetimedb';
import { tables, type DbConnection } from './module_bindings';
import { connect } from './connection';
import { installBridge } from './bridge';
// TODO(mobile): re-enable the QR code and share link (this import, the block below, joinUrl/qrCanvas, and the share block in renderLobby).
// import QRCode from 'qrcode';

const screen = document.getElementById('screen')!;
const errorEl = document.getElementById('error')!;

const NAME_KEY = 'player-name';
const GAME_URL = 'game/index.html';
const urlCode = (new URLSearchParams(location.search).get('room') ?? '').toUpperCase();
// // Set VITE_PUBLIC_URL when the page is served from an address phones cannot reach (or after deploying).
// const publicUrl: string | undefined = import.meta.env.VITE_PUBLIC_URL;
// const base = publicUrl ?? location.origin;
// const onLocalhost = !publicUrl && ['localhost', '127.0.0.1'].includes(location.hostname);
//
// let qrCache: { url: string; canvas: HTMLCanvasElement } | null = null;

let conn: DbConnection | null = null;
let me: Identity | null = null;
let synced = false;
let shownView = '';
// null until checked. The dev server falls back to index.html for unknown paths, so the check looks for a JS content type.
let gameBuilt: boolean | null = null;

function showError(message: string): void {
  errorEl.textContent = message;
}

// Names are user input, so everything is built with textContent, never innerHTML.
function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  props: Partial<HTMLElementTagNameMap[K]> = {},
  ...children: (Node | string)[]
): HTMLElementTagNameMap[K] {
  const node = Object.assign(document.createElement(tag), props);
  node.append(...children);
  return node;
}

async function run(action: () => Promise<void>): Promise<void> {
  showError('');
  try {
    await action();
  } catch (e) {
    showError(e instanceof Error ? e.message : String(e));
  }
}

function renderJoin(): void {
  const name = el('input', {
    placeholder: 'Your name',
    maxLength: 16,
    value: localStorage.getItem(NAME_KEY) ?? '',
    autocomplete: 'name',
  });
  const code = el('input', {
    placeholder: 'Room code',
    maxLength: 4,
    value: urlCode,
    autocapitalize: 'characters',
    autocomplete: 'off',
  });
  const remember = () => localStorage.setItem(NAME_KEY, name.value.trim());

  const join = el('button', { textContent: 'Join game' });
  join.onclick = () => {
    remember();
    void run(() => conn!.reducers.joinRoom({ code: code.value, name: name.value }));
  };
  // Dev shortcut until the Godot host screen creates rooms.
  const create = el('button', { textContent: 'Create room', className: 'secondary' });
  create.onclick = () => {
    remember();
    void run(() => conn!.reducers.createRoom({ name: name.value }));
  };

  screen.replaceChildren(el('h1', { textContent: 'Join a game' }), name, code, join, create);
}

// function joinUrl(code: string): string {
//   return `${base}${location.pathname}?room=${code}`;
// }
//
// // The canvas is reused across lobby re-renders so the code does not flicker.
// function qrCanvas(url: string): HTMLCanvasElement {
//   if (qrCache?.url !== url) {
//     const canvas = el('canvas', { className: 'qr' });
//     void QRCode.toCanvas(canvas, url, { width: 220, margin: 2 });
//     qrCache = { url, canvas };
//   }
//   return qrCache.canvas;
// }

function renderLobby(): void {
  const mine = conn!.db.player.identity.find(me!)!;
  const room = conn!.db.room.code.find(mine.roomCode);
  const players = [...conn!.db.player.iter()]
    .filter(p => p.roomCode === mine.roomCode)
    .sort((a, b) => (a.joinedAt.microsSinceUnixEpoch < b.joinedAt.microsSinceUnixEpoch ? -1 : 1));

  const isHost = !!room && room.host.isEqual(me!);
  const list = el('ul');
  for (const p of players) {
    const isRoomHost = !!room && room.host.isEqual(p.identity);
    const tags = [
      isRoomHost ? 'host' : '',
      p.identity.isEqual(me!) ? 'you' : '',
      !isRoomHost && p.ready ? 'ready' : '',
      p.online ? '' : 'offline',
    ].filter(Boolean);
    list.append(
      el('li', { className: p.online ? '' : 'offline' }, tags.length ? `${p.name} (${tags.join(', ')})` : p.name)
    );
  }

  const leave = el('button', { textContent: 'Leave', className: 'secondary' });
  leave.onclick = () => void run(() => conn!.reducers.leaveRoom({}));

  let action: HTMLButtonElement;
  if (isHost) {
    action = el('button', { textContent: 'Start game' });
    action.onclick = () => void run(() => conn!.reducers.startGame({}));
  } else {
    action = el('button', { textContent: mine.ready ? 'Not ready' : 'Ready' });
    action.onclick = () => void run(() => conn!.reducers.setReady({ ready: !mine.ready }));
  }

  // const url = joinUrl(mine.roomCode);
  // const share: HTMLElement[] = [
  //   qrCanvas(url),
  //   el('a', { href: url, textContent: url, className: 'join-link' }),
  // ];
  // if (onLocalhost) {
  //   share.push(
  //     el('p', {
  //       className: 'hint',
  //       textContent: 'Phones cannot open "localhost". Open this page at the Network address Vite prints, or set VITE_PUBLIC_URL.',
  //     })
  //   );
  // }

  screen.replaceChildren(
    el('h1', { textContent: 'Lobby' }),
    el('p', { className: 'code', textContent: mine.roomCode }),
    // ...share,
    el('p', { textContent: `${players.length} player${players.length === 1 ? '' : 's'}` }),
    list,
    action,
    leave
  );
}

function renderGame(): void {
  const leave = el('button', { textContent: 'Leave', className: 'secondary leave-overlay' });
  leave.onclick = () => void run(() => conn!.reducers.leaveRoom({}));

  if (gameBuilt) {
    screen.replaceChildren(el('iframe', { src: GAME_URL, className: 'game', title: 'Game' }), leave);
  } else {
    screen.replaceChildren(
      el('h1', { textContent: 'Game started' }),
      el('p', { textContent: gameBuilt === null ? 'Loading game...' : 'No Godot web export found. See docs/setup.md.' }),
      leave
    );
  }
}

function render(): void {
  if (!conn || !me || !synced) return;
  const mine = conn.db.player.identity.find(me);
  const started = mine ? !!conn.db.room.code.find(mine.roomCode)?.started : false;
  const view = !mine ? 'join' : started ? 'game' : 'lobby';
  document.body.classList.toggle('playing', view === 'game');
  // The join form and the game iframe must survive unrelated updates (typing, game reload).
  if ((view === 'join' || view === 'game') && shownView === view) return;
  shownView = view;
  if (view === 'lobby') renderLobby();
  else if (view === 'game') renderGame();
  else renderJoin();
}

fetch('game/index.js', { method: 'HEAD' })
  .then(res => res.ok && (res.headers.get('content-type') ?? '').includes('javascript'))
  .catch(() => false)
  .then(ok => {
    gameBuilt = ok;
    if (shownView === 'game') {
      shownView = '';
      render();
    }
  });

screen.replaceChildren(el('p', { textContent: 'Connecting...' }));

connect({
  onConnect(connection, identity) {
    conn = connection;
    me = identity;
    installBridge(connection, identity);
    showError('');
    for (const table of [connection.db.room, connection.db.player]) {
      table.onInsert(render);
      table.onUpdate(render);
      table.onDelete(render);
    }
    connection
      .subscriptionBuilder()
      .onApplied(() => {
        synced = true;
        render();
      })
      .onError(() => showError('Subscription failed'))
      .subscribe([tables.room, tables.player, tables.playerState]);
  },
  onDisconnect() {
    synced = false;
    shownView = '';
    screen.replaceChildren(el('p', { textContent: 'Disconnected. Reload to reconnect.' }));
  },
  onError(error) {
    screen.replaceChildren(el('p', { textContent: 'Could not reach the game server.' }));
    showError(error.message);
  },
});
