# Setup

## Prerequisites

| Tool | Install | Check |
|---|---|---|
| Node.js 20+ | `brew install node` | `node -v` |
| SpacetimeDB CLI | `curl -sSf https://install.spacetimedb.com \| sh` | `spacetime --version` |
| Godot 4.x (standard build) | https://godotengine.org/download | open the editor |

Restart the terminal after installing the SpacetimeDB CLI so `spacetime` is on `PATH`.

## Local development

```sh
spacetime start   # local server on 127.0.0.1:3000 (leave running)

cd spacetimedb/spacetimedb && npm install   # first time only
cd .. && spacetime publish --server local --module-path spacetimedb -y platformer-6ea8r

spacetime call --server local platformer-6ea8r create_room Lily
spacetime sql --server local platformer-6ea8r "SELECT * FROM room"
spacetime logs --server local platformer-6ea8r
```

`spacetimedb/spacetime.json` defaults to Maincloud, so always pass `--server local` until we deploy.

## Web client

```sh
cd web
npm install
npm run generate   # regenerate src/module_bindings after any schema or reducer change
npm run dev        # http://localhost:5173, also served on the LAN
```

The page connects to SpacetimeDB on the same host that served it (`ws://<host>:3000`). Open the lobby on `http://localhost:5173` for development; other browser tabs or profiles on the same laptop join by typing the room code, or with `?room=ABCD` in the URL. The QR code and share link are commented out in `web/src/main.ts` until we work on mobile play (search for `TODO(mobile)`).

The lobby also loads from a phone on the same Wi-Fi at `http://192.168.x.x:5173`, but the game itself will not load there: Godot web exports require a secure context (HTTPS or `localhost`), and an HTTPS page cannot talk to `ws://` either. Playing on a phone therefore needs the Maincloud deployment with the page hosted over HTTPS.

Override the target with `VITE_STDB_URI` and `VITE_STDB_DB` (for example in `web/.env.local`).

## Running the game inside the web page

The web page owns the SpacetimeDB connection and embeds the Godot web export in an iframe once the host starts the game. Godot reaches the connection through the `Stdb` autoload (`game/stdb.gd`), which calls `window.stdb` from `web/src/bridge.ts`.

1. In Godot, choose Project > Export > Add > Web.
2. Set the export path to `web/public/game/index.html` (relative to the repo root) and export.
3. Run `npm run dev` in `web/`, create a room, and start the game. The export is git-ignored, so each teammate exports their own copy.

Re-export after every change to the game. `Stdb` calls do nothing when the game runs from the editor.
Maincloud (hosted) setup comes later; local is enough until the demo.
