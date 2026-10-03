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

The web page owns the SpacetimeDB connection and embeds the Godot web export in an iframe once the host starts the game. Godot reaches the connection through two autoloads registered in `game/project.godot`:

- `Stdb` (`game/stdb.gd`) wraps `window.stdb` from `web/src/bridge.ts`.
- `Netplay` (`game/netplay.gd`) publishes the node named `Player` about 20 times a second and shows every other player in the room as a tinted ghost with their name. It needs no changes to `player.gd` or the level, so keep the player node named `Player`.

1. In Godot, choose Project > Export > Add > Web (the repo already has a Web preset in `game/export_presets.cfg`).
2. Export to `web/public/game/index.html` and export.
3. Run `npm run dev` in `web/`, create a room, and start the game. The export is git-ignored, so each teammate exports their own copy.

Re-export after every change to the game. `Stdb` and `Netplay` do nothing when the game runs from the editor.

To test two players on one laptop, use two separate browser profiles or one normal and one incognito window (tabs in the same profile share one identity).

## Maincloud (hosted)

The module is deployed to Maincloud as database `mhacks26-platformer` (dashboard: https://spacetimedb.com/mhacks26-platformer).

```sh
spacetime login   # once, links the CLI to your SpacetimeDB account
cd spacetimedb
spacetime publish --server maincloud --module-path spacetimedb -y mhacks26-platformer
```

Only the account that created the database can publish to it. Run `spacetime sql --server maincloud mhacks26-platformer "SELECT * FROM room"` from outside the repo, because `spacetimedb/spacetime.local.json` otherwise overrides the database name.

The web client reads `web/.env.production` (`wss://maincloud.spacetimedb.com`, `mhacks26-platformer`):

```sh
cd web
npm run dev:cloud   # dev server that talks to Maincloud
npm run build       # production build in web/dist, includes the Godot export from web/public/game
```

`web/dist` is a static site. Host it on any HTTPS static host that allows a 40 MB file (the Godot `.wasm`); Cloudflare Pages does not.

### Deploying to GitHub Pages

The site is served from the `gh-pages` branch at `https://kadesole22.github.io/MHACKS/`.

1. Export the game from Godot into `web/public/game` (see above).
2. Run `./scripts/deploy-pages.sh`. It builds the site and force-pushes `web/dist` to the `gh-pages` branch, so the 40 MB game export never enters `main`'s history.
3. First time only: in the GitHub repo go to Settings > Pages, set Source to "Deploy from a branch", branch `gh-pages`, folder `/ (root)`. Pages on a private repo needs a paid plan, so the repo must be public.

Redeploy with the same script after changing the game or the web client.
