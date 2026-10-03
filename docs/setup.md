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

The page connects to SpacetimeDB on the same host that served it (`ws://<host>:3000`). To test from a phone, open the `Network:` URL Vite prints on the same Wi-Fi, for example `http://192.168.x.x:5173/?room=ABCD`. Campus Wi-Fi often isolates devices from each other, so use a phone hotspot if it cannot connect.

Override the target with `VITE_STDB_URI` and `VITE_STDB_DB` (for example in `web/.env.local`).

Maincloud (hosted) setup comes later; local is enough until the demo.
