import type { Identity } from 'spacetimedb';
import { DbConnection } from './module_bindings';

// Defaults to the host serving this page, so a phone on the LAN reaches the laptop's local SpacetimeDB.
const uri: string = import.meta.env.VITE_STDB_URI ?? `ws://${location.hostname}:3000`;
const dbName: string = import.meta.env.VITE_STDB_DB ?? 'platformer-6ea8r';
const tokenKey = `stdb-token:${uri}/${dbName}`;

export function connect(handlers: {
  onConnect: (conn: DbConnection, identity: Identity) => void;
  onDisconnect: () => void;
  onError: (error: Error) => void;
}): void {
  DbConnection.builder()
    .withUri(uri)
    .withDatabaseName(dbName)
    .withToken(localStorage.getItem(tokenKey) ?? undefined)
    .onConnect((conn, identity, token) => {
      localStorage.setItem(tokenKey, token);
      handlers.onConnect(conn, identity);
    })
    .onDisconnect(() => handlers.onDisconnect())
    .onConnectError((_ctx, error) => handlers.onError(error))
    .build();
}
