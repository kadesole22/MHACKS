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

spacetime call --server local platformer-6ea8r say_hello
spacetime logs --server local platformer-6ea8r
```

`spacetimedb/spacetime.json` defaults to Maincloud, so always pass `--server local` until we deploy.

Maincloud (hosted) setup comes later; local is enough until the demo.
