# Architecture

- **SpacetimeDB module** (`spacetimedb/`, TypeScript): rooms, players, and game state. This is the entire backend.
- **Godot game** (`game/`): one Web export used by both host and phones. The host shows a room code and QR code; phones open the URL.
- **Godot to SpacetimeDB**: the web build calls the SpacetimeDB TypeScript SDK through `JavaScriptBridge`.
- **Sync model**: each client simulates its own player and publishes position through a reducer at about 15-20 Hz. Other clients interpolate.
