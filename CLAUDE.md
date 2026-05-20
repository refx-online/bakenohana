# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
shards install          # install dependencies
crystal run --release src/bakenohana.cr  # run the server
crystal spec            # run tests
shards build            # compile binary
```

Single spec file: `crystal spec spec/packet_spec.cr`

## Environment

Copy `.env_` to `.env` and fill in values before running. Required vars:

| Var | Purpose |
|-----|---------|
| `PORT` | HTTP listen port |
| `DB_HOST/PORT/NAME/USER/PASS` | MySQL connection |
| `AVA_PATH` | Directory for avatar images (relative to cwd) |
| `BOAT_PREFIX` | Bot command prefix (default `?`) |
| `MAP_MIRROR_API` | Base URL for beatmap downloads |
| `OSU_API_KEY` | osu! API key |
| `DEBUG` | Set `true` to enable `rlog` output |

## Architecture

bakenohana is a Crystal implementation of the osu! Bancho protocol — the real-time TCP-over-HTTP server that the osu! client talks to.

### Subdomain routing

Kemal handles all HTTP, but `Middleware::Dispatcher` (`src/app/middleware.cr`) intercepts every request and dispatches by subdomain before Kemal's own router runs. Routes are registered in `init_routes` (`src/app/init_router.cr`):

- `c`, `ce`, `c4`, `c5`, `c6` → `Cho` (Bancho protocol)
- `a` → `Ava` (avatar serving)
- `osu` → `Web` (registration, map redirects)

### Login / packet loop (Cho)

`POST /` on a bancho subdomain is the single endpoint for all client communication. The osu! client sends requests without an `osu-token` header on first contact (login), and with one on every subsequent poll.

- **Login path**: parses the 3-line login body, authenticates via `Auth` (bcrypt), creates a `Player`, builds a burst of server packets (presence, stats, channels, friends list), and returns them with a `cho-token` header.
- **Packet path**: reads the token, looks up the `Player` in `PlayerSession`, feeds the body through `BanchoPacketReader`, calls `handle(player)` on each parsed packet, then flushes `player.dequeue` as the response body.

### Packet system

`BanchoPacketReader` (`src/app/packets/reader.cr`) is an `Iterator(BasePacket)` that walks a `Bytes` slice, reads the 7-byte header (id u16 + pad + len u32), and returns the registered `BasePacket` subclass for that id. Unknown packet ids are skipped.

Packet classes are registered with the `register` macro at the bottom of `reader.cr`. Each class reads its own fields from the reader in `initialize`, then acts on a `Player` in `handle`.

Server-to-client packets are built by `Packets.write` (`src/app/packets/packets.cr`), which takes a `ServerPacket` enum value and typed `{value, OsuType}` tuples, serialises them little-endian, and returns a `Bytes` slice. Convenience methods (`Packets.user_stats`, `Packets.send_message`, etc.) wrap `write`.

### In-memory state

All live state is in two modules in `src/app/state/sessions.cr`:

- **`PlayerSession`** — `Hash(String, Player)` keyed by token, plus a hardcoded bot player. All access is mutex-guarded. Lookup by token, id, or username.
- **`ChannelSession`** — `Array(Channels)` loaded from the DB at startup (`ChannelSession.prepare`), plus dynamically created instance channels (spectator: `#spec_<id>`, multiplayer: `#multi_<id>`). Instance channels are removed when their last member leaves.

`Player` (`src/app/objects/player.cr`) owns a mutex-protected `IO::Memory` queue. Packets are written to it with `enqueue(Bytes)` and consumed atomically with `dequeue : Bytes`.

### Repo layer

Repo structs (`src/app/repo/`) include `DB::Serializable` and expose class methods (`fetch_one`, `fetch_all`, `create`, `update`) that call `Services.db` directly. `Services.db` is a thin wrapper around `crystal-db` initialised once at startup.

### Geolocation

`Geoloc` (`src/app/state/geoloc.cr`) is an LRU cache (256 entries) backed by `ip-api.com`. Called during login to set lat/lon/country on the player's status.

### Performance calculation

`OsuPerformanceCalculator` (`src/app/state/performance.cr`) calls into `librosu_ffi.so` via Crystal's C FFI. The `.so` must be present at `src/app/lib/native/librosu_ffi.so` at compile time (see [remeliah/rosu-ffi](https://github.com/remeliah/rosu-ffi/)).

### Gamemode encoding

`Gamemode` (`src/app/consts/mode.cr`) extends the 4 vanilla modes with Relax (+4) and Autopilot (+8) variants. `ChangeActionPacket` remaps the client's raw mode+mods into this internal enum. `as_vn` strips the modifier offset back to 0–3 for wire encoding.
