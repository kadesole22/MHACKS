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
spacetime start   # local server on 127.0.0.1:3000
```

Maincloud (hosted) setup comes later; local is enough until the demo.
