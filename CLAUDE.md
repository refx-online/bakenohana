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
| `REDIS_URL` | Redis connection URL (default `redis://localhost:6379`) |
| `DOMAIN` | Public domain name (used in webhook URLs) |
| `BOAT_PREFIX` | Bot command prefix (default `?`) |
| `MAP_MIRROR_API` | Base URL for beatmap downloads |
| `OSU_API_KEY` | osu! API key |
| `OMAJINAI_URL` | Score server base URL (default `http://localhost:5000`) |
| `DISCORD_RANK_WEBHOOK` | Optional Discord webhook for map rank changes |
| `DEBUG` | Set `true` to enable `rlog` output |

## Architecture

bakenohana is a Crystal implementation of the osu! Bancho protocol — the real-time TCP-over-HTTP server that the osu! client talks to.

### Request handling

Kemal handles all HTTP. Routes are registered at startup in `bakenohana.cr` via `Cho.register_routes` and `Api::V1.register_routes`. A `Metrics` Kemal handler (`src/app/middleware.cr`) logs request timing and status for every request.

`POST /` is the single endpoint for all Bancho client communication. Requests without `osu-token` = login; with token = packet loop.

- **Login path** (`src/app/packets/handlers/login.cr`): parses the 3-line login body, authenticates via `Auth` (bcrypt + hardware ID conflict check via `UserHashRepo`), creates a `Player`, runs `burst` to build the initial packet payload (presence, stats, channels, friends list, silence end), and returns it with a `cho-token` header. Logs the login via `IngameLoginRepo`.
- **Packet path** (`src/app/routes/main_handler.cr`): looks up the player by token, feeds the body through `BanchoPacketReader` using `PACKET_MAP` (or `RESTRICTED_PACKET_MAP` for restricted players), calls `handle(player)` on each packet, updates `last_recv_time`, then flushes `player.dequeue` as the response body.

A background fiber in `bakenohana.cr` checks every 100s and calls `player.logout` on any player whose `last_recv_time` is >300s ago (ghost disconnect).

### Packet system

`BanchoPacketReader` (`src/app/packets/reader.cr`) is an `Iterator(BasePacket)` that walks a `Bytes` slice, reads the 7-byte header (id u16 + pad + len u32), and dispatches to the registered `BasePacket` subclass. Unknown ids are skipped. Packet classes are registered with the `register` macro at the bottom of `reader.cr`; each reads its fields in `initialize` and acts on a `Player` in `handle`.

Server-to-client packets are built by `Packets.write` (`src/app/packets/packets.cr`), which takes a `ServerPacket` enum value and typed `{value, OsuType}` tuples, serialises them little-endian, and returns `Bytes`. Convenience methods (`Packets.user_stats`, `Packets.send_message`, etc.) wrap `write`.

### In-memory state

- **`PlayerSession`** (`src/app/state/sessions.cr`) — `Hash(String, Player)` keyed by token, plus a hardcoded bot player (`id: 1, username: "boat"`). All access is mutex-guarded. Lookup by token, id, or username.
- **`ChannelSession`** (`src/app/state/sessions.cr`) — `Array(Channels)` loaded from DB at startup, plus dynamically created instance channels (`#spec_<id>`, `#multi_<id>`). Instance channels are removed when their last member leaves.
- **`MatchSession`** (`src/app/state/match_session.cr`) — fixed-size `Array(Match?)` of 64 slots, indexed by match id. All access is mutex-guarded.

`Player` owns a mutex-protected `IO::Memory` queue. Packets are written with `enqueue(Bytes)` and consumed atomically with `dequeue : Bytes`.

`player.refx` (Bool) marks a re;fx custom client user. `player.refx_lb` (Int32) selects their leaderboard variant (0 = vanilla, 1/2 = cheat, 5/6 = cheatcheat). `Player#resolve_mode` uses these to remap the wire mode byte before stats lookups. `Packets.user_stats` allows pp values above `Int32::MAX` for refx players by routing them through `rscore`.

### Repo layer

Repo structs (`src/app/repo/`) include `DB::Serializable` and expose class methods (`fetch_one`, `fetch_all`, `create`, `update`) that call `Services.db` directly. `Services.db` is a `Database` wrapper around `crystal-db` initialised once at startup.

### Gamemode encoding

`Gamemode` (`src/app/consts/mode.cr`) is a `UInt8` enum extending the 4 vanilla modes (0–3) with: Relax (4–7), Autopilot (8–11), Cheat (12–15), CheatCheat (16–19), TouchDevice (20). `as_vn` returns `value % 4` to strip the variant offset back to 0–3 for wire encoding. `VALID_GAMEMODES` excludes RX_MANIA, AP_TAIKO, AP_CATCH, AP_MANIA.

### Geolocation

`Geoloc` (`src/app/state/geoloc.cr`) resolves country/lat/lon at login. Priority: `CF-IPCountry` header → `X-Country-Code` header → `ip-api.com` HTTP call. Private/empty IPs skip the external call and return `"xx"`.

### Performance calculation

`OsuPerformanceCalculator` (`src/app/state/performance.cr`) calls into `librosu_ffi.so` via Crystal's C FFI. The `.so` must be present at `src/app/lib/native/librosu_ffi.so` at compile time (see [remeliah/rosu-ffi](https://github.com/remeliah/rosu-ffi/)).

### Redis

`RedisService` (`src/app/state/redis.cr`) holds two connections: one for commands, one dedicated to pub/sub. Leaderboards are sorted sets keyed `bancho:leaderboard:<mode>` and `bancho:leaderboard:<mode>:<country>`, scored by pp. Rank via `ZREVRANK`.

`PubSub` (`src/app/state/pubsub.cr`) subscribes to four channels published by the score server:

| Channel | Payload | Effect |
|---------|---------|--------|
| `refx:notify` | `user_id\|message` | Send notification packet to player |
| `refx:restrict` | `user_id\|reason` | Strip `UNRESTRICTED`, send restricted packet, remove from leaderboards |
| `refx:refresh_stats` | `user_id` | Reload stats from DB, update leaderboards, broadcast stats packet |
| `refx:recalculate` | `user_id` | Same as refresh_stats, then DM player via bot |

The `map` command publishes `forlorn:refresh_map` with the beatmap MD5 to notify the score server of a status change.

### Bot commands

`CommandHandler` (`src/app/objects/commands.cr`) uses a `command` macro to register bot commands. Commands trigger when a chat message starts with `Config.boat_prefix` (default `?`).

```crystal
command "name", "description",
  arg("argname", "type", required, default),
  aliases: ["alias"],
  priv: Privileges::MODERATOR do
  # `player` and `parsed_args` are in scope
end
```

Privilege-gated commands (`priv:`) are hidden from `?help` and return "unknown command" to unprivileged players.

### Internal API

`GET /api/v1/get_player_count` and `GET /api/v1/get_player_status` are registered under `Api::V1` and served on the bancho subdomain alongside the Bancho protocol.
