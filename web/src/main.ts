import './style.css';
import type { Identity } from 'spacetimedb';
import { tables, type DbConnection } from './module_bindings';
import { connect } from './connection';

const screen = document.getElementById('screen')!;
const errorEl = document.getElementById('error')!;

const NAME_KEY = 'player-name';
const urlCode = (new URLSearchParams(location.search).get('room') ?? '').toUpperCase();

let conn: DbConnection | null = null;
let me: Identity | null = null;
let synced = false;
let shownView = '';

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

function renderLobby(): void {
  const mine = conn!.db.player.identity.find(me!)!;
  const room = conn!.db.room.code.find(mine.roomCode);
  const players = [...conn!.db.player.iter()]
    .filter(p => p.roomCode === mine.roomCode)
    .sort((a, b) => (a.joinedAt.microsSinceUnixEpoch < b.joinedAt.microsSinceUnixEpoch ? -1 : 1));

  const list = el('ul');
  for (const p of players) {
    const tags = [
      room && room.host.isEqual(p.identity) ? 'host' : '',
      p.identity.isEqual(me!) ? 'you' : '',
      p.online ? '' : 'offline',
    ].filter(Boolean);
    list.append(
      el('li', { className: p.online ? '' : 'offline' }, tags.length ? `${p.name} (${tags.join(', ')})` : p.name)
    );
  }

  const leave = el('button', { textContent: 'Leave', className: 'secondary' });
  leave.onclick = () => void run(() => conn!.reducers.leaveRoom({}));

  screen.replaceChildren(
    el('h1', { textContent: 'Lobby' }),
    el('p', { className: 'code', textContent: mine.roomCode }),
    el('p', { textContent: `${players.length} player${players.length === 1 ? '' : 's'}` }),
    list,
    leave
  );
}

function render(): void {
  if (!conn || !me || !synced) return;
  const view = conn.db.player.identity.find(me) ? 'lobby' : 'join';
  // The join form is not re-rendered on unrelated updates so typing is not interrupted.
  if (view === 'join' && shownView === 'join') return;
  shownView = view;
  if (view === 'lobby') renderLobby();
  else renderJoin();
}

screen.replaceChildren(el('p', { textContent: 'Connecting...' }));

connect({
  onConnect(connection, identity) {
    conn = connection;
    me = identity;
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
      .subscribe([tables.room, tables.player]);
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
