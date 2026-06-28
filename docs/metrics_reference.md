# Metrics Reference

All metrics are prefixed with `gmod.` for easy filtering.

## Server Performance (`sv_server.lua`)

| Metric | Type | Description |
|--------|------|-------------|
| `gmod.server.tickrate` | Gauge | Configured server tick rate (`Hz`) |
| `gmod.server.tick_interval` | Gauge | Time between server ticks (`s`) |
| `gmod.server.frametime` | Gauge | Actual server frame time (`s`) |
| `gmod.server.fps` | Gauge | Server frames per second |
| `gmod.server.lua_memory` | Gauge | Lua state memory usage (`bytes`) |
| `gmod.server.uptime` | Gauge | Server uptime (`s`) |
| `gmod.server.max_players` | Gauge | Maximum player slots (`{players}`) |
| `gmod.server.tick_duration` | Gauge | Ratio of frameTime to tickInterval. > 1 means overloaded |
| `gmod.server.collection_duration` | Gauge | Time spent collecting and sending in the last cycle (`s`) |
| `gmod.telemetry.active` | Gauge | Always 1 — indicates gTelemetry is running |
| `gmod.telemetry.collection_errors` | Sum | Cumulative collector errors since server start (`{errors}`) |
| `gmod.telemetry.send_failures` | Sum | Cumulative HTTP send failures since server start (`{failures}`) |

## Players (`sv_players.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.players.count` | Gauge | — | Connected player count (`{players}`) |
| `gmod.players.bots` | Gauge | — | Connected bot count (`{players}`) |
| `gmod.players.ping` | Gauge | `player.name`, `player.steam_id` | Per-player ping (`ms`) |
| `gmod.players.ping_avg` | Gauge | — | Average ping across humans (`ms`) |
| `gmod.players.client_fps` | Gauge | `player.name`, `player.steam_id` | Client-reported FPS |
| `gmod.players.kills` | Sum | `player.name`, `player.steam_id` | Cumulative kills |
| `gmod.players.deaths` | Sum | `player.name`, `player.steam_id` | Cumulative deaths |
| `gmod.players.connection_time` | Gauge | `player.name`, `player.steam_id` | Time connected (s) |
| `gmod.players.load_time` | Gauge | `player.name`, `player.steam_id` | Connect-to-ready time (s). Internal sentinel `-1` if client never reports ready within 120s; not emitted as metric value |

## Entities (`sv_entities.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.entities.total` | Gauge | — | Total entity count |
| `gmod.entities.by_type` | Gauge | `entity.type`, `entity.owner` | Entities grouped by type (prop, ragdoll, npc, weapon, vehicle, door, scripted_ent, constraint, effect, other) and owner (world \| player) |
| `gmod.physics.objects` | Gauge | — | Entities with an active physics object |
| `gmod.entities.owned_by_player` | Gauge | `player.name`, `player.steam_id`, `entity.type`, `entity.class` | Entities owned per player, grouped by type |

## Network (`sv_network.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.network.net_messages_out` | Sum | — | Net library messages started by the server (`net.Start` calls, `{messages}`). May overcount if sends are conditionally aborted |
| `gmod.network.net_messages_in` | Sum | — | Net library messages received by the server (via wrapped `net.Receive` callbacks, `{messages}`). A single message may be counted multiple times if multiple receivers are registered for the same message name |
| `gmod.network.messages_out_details` | Sum | `net.message` | Per-message-name sent breakdown (`{messages}`) |
| `gmod.network.messages_in_details` | Sum | `net.message` | Per-message-name received breakdown (`{messages}`) |
| `gmod.network.active_receivers` | Gauge | — | Total registered net message receivers (`{receivers}`) |
| `gmod.network.packet_loss_avg` | Gauge | — | Average packet loss (%) |
| `gmod.network.packet_loss` | Gauge | `player.name`, `player.steam_id` | Per-player packet loss (%) |

## Hooks & Errors (`sv_hooks.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.hooks.count` | Gauge | — | Total registered hooks (`{hooks}`) |
| `gmod.hooks.think_total` | Sum | — | Cumulative Think hook executions (`{calls}`) |
| `gmod.hooks.tick_total` | Sum | — | Cumulative Tick hook executions (`{calls}`) |
| `gmod.hooks.think_time` | Gauge | — | Time spent in Think hooks last frame (`s`) |
| `gmod.hooks.tick_time` | Gauge | — | Time spent in Tick hooks last tick (`s`) |
| `gmod.lua.errors` | Sum | — | Cumulative Lua error count (`{errors}`) |
| `gmod.hooks.by_event` | Gauge | `hook.event` | Hooks per event type — top 20 (`{hooks}`) |

## Map & Server Info (`sv_map.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.server.info` | Gauge | `server.map`, `server.gamemode`, `server.hostname`, `server.ip` | Server info (always 1, `{info}`). `server.ip` is captured once at first collection and cached for the process lifetime |
| `gmod.map.changes` | Sum | — | Map change count (`{changes}`) |

## Chat & Admin (`sv_chat.lua`)

| Metric | Type | Description |
|--------|------|-------------|
| `gmod.chat.messages` | Sum | Total chat messages (`{messages}`) |
| `gmod.admin.commands` | Sum | Admin commands executed (`{commands}`) |

## DarkRP Economy (`sv_darkrp.lua`)

*Only available when DarkRP is detected.*

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.darkrp.money_total` | Gauge | — | Total money in circulation (`{currency}`) |
| `gmod.darkrp.money_avg` | Gauge | — | Average money per player (`{currency}`) |
| `gmod.darkrp.job_count` | Gauge | `darkrp.job` | Players per job (`{players}`) |
| `gmod.darkrp.props_per_player` | Gauge | `player.name`, `player.steam_id` | Props per player (`{props}`) |
| `gmod.darkrp.wanted_count` | Gauge | — | Wanted players (`{players}`) |
| `gmod.darkrp.arrested_count` | Gauge | — | Arrested players (`{players}`) |
| `gmod.darkrp.money_per_player` | Gauge | `player.name`, `player.steam_id` | Money per player (`{currency}`) |
