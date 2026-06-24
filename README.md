# gTelemetry — GMod Telemetry

A Garry's Mod server monitoring addon that exports telemetry **metrics** and **logs** to **Grafana** via **Grafana Alloy** using the **OpenTelemetry (OTLP/HTTP JSON)** protocol.

Monitor server performance, players, entities, network, Lua errors, and more from Grafana dashboards. Optionally send server events (chat, joins, deaths, admin commands, errors) to **Loki** for log analysis.

```
┌─────────────────────┐  HTTP POST (OTLP/JSON)  ┌─────────────────────┐
│    GMod Server      │  ─────────────────────> │   Grafana Alloy     │
│  ┌───────────────┐  │   :4318/v1/metrics      │  otelcol receiver   │
│  │  gTelemetry   │  │  ─────────────────────> │  (metrics + logs)   │
│  │    (Lua)      │  │   :4318/v1/logs         └──────────┬──────────┘
│  └───────────────┘  │                                    │
│  ┌───────────────┐  │                         ┌──────────┴──────────┐
│  │ Client module │  │                         │                     │
│  │ (FPS data)    │  │                    ┌────┴─────┐         ┌─────┴────┐
│  └───────────────┘  │                    │Prometheus│         │  Loki    │
└─────────────────────┘                    └────┬─────┘         └─────┬────┘
                                                 └──────────┬──────────┘
                                                      ┌─────┴─────┐
                                                      │  Grafana  │
                                                      └───────────┘
```

## Features

- **~59 metrics** across 8 collectors + **Loki log export** (optional)
- **10 log event types** — chat, player join/leave, deaths, Lua errors, admin commands (ULX, SAM, FAdmin), map changes, server start/stop
- **Event-driven logging** — hooks capture events in real-time with buffered flush, no polling
- **Zero dependencies** — uses native GMod `HTTP()` function
- **OTLP standard** — compatible with any OpenTelemetry-compatible backend
- **DarkRP auto-detection** — economic metrics load automatically when DarkRP is present
- **Client FPS tracking** — collects client performance data via net library
- **Admin mod detection** — automatically hooks into ULX, SAM, and FAdmin for command tracking
- **Entity ownership breakdown** — per-player entity counts grouped by type (configurable)
- **Network message details** — per-message-name breakdown (configurable, high-cardinality gated)
- **Configurable** — all settings via server ConVars, runtime reconfiguration without restart
- **Late-init support** — works even if loaded after map start (e.g., via `lua_openscript`)
- **Graceful shutdown** — sends final metrics push and log flush on server shutdown
- **Lightweight** — minimal performance impact, async HTTP sends, error-isolated collectors, configurable entity scan interval
- **Resilient** — exponential backoff on HTTP failures (up to 2 minutes), health metrics for pipeline monitoring
- **Alert-ready** — includes [ready-to-use Grafana alert rules](docs/alert_rules.md) for anomaly detection

## Installation

1. Copy the addon folder to your GMod server's `addons` directory:

   ```
   garrysmod/addons/gTelemetry/
   ├── lua/
   │   ├── autorun/
   │   │   ├── server/gtelemetry_init.lua
   │   │   └── client/cl_gtelemetry.lua
   │   └── gtelemetry/
   │       ├── sv_config.lua
   │       ├── sv_otlp.lua
   │       ├── sv_otlp_logs.lua
   │       └── collectors/
   │           ├── sv_server.lua
   │           ├── sv_players.lua
   │           ├── sv_entities.lua
   │           ├── sv_network.lua
   │           ├── sv_hooks.lua
   │           ├── sv_map.lua
   │           ├── sv_chat.lua
   │           ├── sv_darkrp.lua
   │           └── sv_log_events.lua
   ├── docs/
   │   ├── alloy_example.hcl
   │   ├── alert_rules.md
   │   └── discord_templates.md
   ├── README.md
   └── LICENSE
   ```

2. **Required:** Start your server with `-allowlocalhttp` to allow HTTP to private IPs:

   ```
   srcds.exe -game garrysmod +gamemode sandbox +map gm_construct -allowlocalhttp
   ```

3. Restart the server, or run `lua_openscript autorun/server/gtelemetry_init.lua` in the console for a hot-reload.

## Configuration

All settings are managed via server ConVars — no config files.

### Metrics ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `gtelemetry_enabled` | `1` | Master enable/disable switch |
| `gtelemetry_endpoint` | `http://localhost:4318/v1/metrics` | Alloy OTLP HTTP endpoint URL |
| `gtelemetry_interval` | `10` | Collection and push interval in seconds (1-300) |
| `gtelemetry_service_name` | `gmod-server` | OTLP `service.name` resource attribute |
| `gtelemetry_auth_token` | *(empty)* | Optional Bearer token for Alloy authentication |
| `gtelemetry_debug` | `0` | Enable verbose debug logging to server console |
| `gtelemetry_darkrp` | `1` | Enable DarkRP economic metrics (still requires DarkRP) |
| `gtelemetry_entities_per_player` | `1` | Enable per-player entity ownership breakdown (high cardinality) |
| `gtelemetry_entities_interval` | `1` | Collect entity metrics every N cycles (1 = every cycle). Higher values reduce CPU on large maps |
| `gtelemetry_network_details` | `0` | Enable per-message-name net message breakdown (high cardinality) |
| `gtelemetry_version` | `1.5.0` | Version info (replicated to clients) |

### Log ConVars

| ConVar | Default | Description |
|--------|---------|-------------|
| `gtelemetry_log_enabled` | `0` | Enable OTLP log collection and export to Loki via Alloy |
| `gtelemetry_log_endpoint` | `http://localhost:4318/v1/logs` | OTLP HTTP endpoint for log export |
| `gtelemetry_log_interval` | `10` | Log flush interval in seconds (1-300) |
| `gtelemetry_log_buffer_size` | `1000` | Maximum log entries buffered before dropping oldest (100-10000) |

### How intervals work — metrics

gTelemetry uses a **3-level pipeline** for metrics:

```
┌─ LEVEL 1: Client measurement ─────────────────────────────┐
│  Client FPS timer (hardcoded 5s):                         │
│  Measures local FPS every 5 seconds and sends to server   │
│  via net message. The server caches the latest value.     │
└──────────────────────────────┬────────────────────────────┘
                               │
┌─ LEVEL 2: Collector sampling ────────────────────────────┐
│  gtelemetry_interval (default 10s):                      │
│  Triggers CollectAndSend() which calls every collector.  │
│  Each collector re-samples its data at this moment.      │
│                                                          │
│  gtelemetry_entities_interval (default 1):               │
│  Controls how many cycles pass between entity scans.     │
│  At 5, entities are scanned every 5th cycle (every 50s  │
│  if gtelemetry_interval is 10).                          │
└──────────────────────────────┬───────────────────────────┘
                               │
┌─ LEVEL 3: Export to Alloy ───────────────────────────────┐
│  gtelemetry_interval (default 10s):                      │
│  The same timer. After collecting, the payload is built  │
│  and sent via HTTP POST. Decides how often data arrives  │
│  in Prometheus / Grafana.                                │
└──────────────────────────────────────────────────────────┘
```

Key points:
- **gtelemetry_interval** = both sampling trigger AND export interval
- **gtelemetry_entities_interval** = skip N-1 cycles between entity scans. Only affects entity metrics
- **Client FPS** is sent every 5s regardless of the interval. The server uses the last received value on each collect cycle
- All metrics use the collection timestamp (standard for Prometheus gauges, does not affect rate calculations)

### How intervals work — logs

The log pipeline is **independent** from metrics:

| Timing | Setting | Notes |
|--------|---------|-------|
| Event capture | Real-time via hooks | No polling — hooks fire instantly and queue log entries |
| Buffer flush | `gtelemetry_log_interval` (default 10s) | Timer-based flush of the accumulated buffer |
| Export | Same as flush interval | HTTP POST to the configured log endpoint |

Logs are buffered as they happen and flushed periodically. This avoids one HTTP request per event while keeping log delivery near real-time. If the buffer exceeds `gtelemetry_log_buffer_size`, the oldest entries are dropped.

### Example server.cfg

```
// gTelemetry — metrics
gtelemetry_enabled 1
gtelemetry_endpoint "http://192.168.1.100:4318/v1/metrics"
gtelemetry_interval 15
gtelemetry_service_name "my-darkrp-server"

// gTelemetry — logs (optional)
gtelemetry_log_enabled 1
gtelemetry_log_endpoint "http://192.168.1.100:4318/v1/logs"
gtelemetry_log_interval 10
```

## Backend Setup

### Grafana Alloy

1. Install Alloy following the [official guide](https://grafana.com/docs/alloy/latest/get-started/install/)
2. Create a `config.alloy` file with the metrics pipeline enabled by default and Loki logs as an optional block:

   ```hcl
   // ════════════════════════════════════════════════════════════
   // OTLP Receiver — accepts metrics (+ optionally logs)
   // from gTelemetry via HTTP on port 4318
   // ════════════════════════════════════════════════════════════
   otelcol.receiver.otlp "gmod" {
       http {
           endpoint = "0.0.0.0:4318"
       }
       output {
           metrics = [otelcol.processor.batch.default.input]
           // Uncomment for Loki log support:
           // logs    = [otelcol.processor.batch.logs.input]
       }
   }

   // ════════════════════════════════════════════════════════════
   // Metrics pipeline — Prometheus remote_write
   // ════════════════════════════════════════════════════════════
   otelcol.processor.batch "default" {
       timeout = "5s"
       send_batch_size = 1000
       output {
           metrics = [otelcol.exporter.prometheus.default.input]
       }
   }

   otelcol.exporter.prometheus "default" {
       forward_to = [prometheus.remote_write.default.receiver]
   }

   prometheus.remote_write "default" {
       endpoint {
           url = "http://localhost:9090/api/v1/write"
       }
   }

   // ════════════════════════════════════════════════════════════
   // Optional: Loki log pipeline
   // Uncomment the section below and set gtelemetry_log_enabled 1
   // ════════════════════════════════════════════════════════════
   // otelcol.processor.batch "logs" {
   //     timeout = "5s"
   //     send_batch_size = 500
   //     output {
   //         logs = [loki.write.default.input]
   //     }
   // }
   //
   // loki.write "default" {
   //     endpoint {
   //         url = "http://localhost:3100/loki/api/v1/push"
   //     }
   // }
   ```

3. Run: `alloy run config.alloy`
4. Verify Alloy is receiving data at `http://localhost:12345` (Alloy's built-in UI)

See [`docs/alloy_example.hcl`](docs/alloy_example.hcl) for additional options (InfluxDB, dual export, auth).

### Grafana dashboards

1. Add Prometheus and/or Loki as data sources
2. Create dashboards using the metrics listed below (all prefixed `gmod.`)
3. See [`docs/alert_rules.md`](docs/alert_rules.md) for ready-to-use PromQL alert rules
4. See [`docs/discord_templates.md`](docs/discord_templates.md) for Discord notification embeds

## Metrics Reference

### Server Performance (`sv_server.lua`)

| Metric | Type | Description |
|--------|------|-------------|
| `gmod.server.tickrate` | Gauge | Configured server tick rate (Hz) |
| `gmod.server.tick_interval` | Gauge | Time between server ticks (s) |
| `gmod.server.frametime` | Gauge | Actual server frame time (s) |
| `gmod.server.fps` | Gauge | Server frames per second |
| `gmod.server.lua_memory` | Gauge | Lua state memory usage (bytes) |
| `gmod.server.uptime` | Gauge | Server uptime since map load (s) |
| `gmod.server.max_players` | Gauge | Maximum player slots |
| `gmod.server.tick_duration` | Gauge | Ratio of frameTime to tickInterval. > 1 means overloaded |
| `gmod.server.collection_duration` | Gauge | Time spent collecting and sending in the last cycle (s) |
| `gmod.telemetry.active` | Gauge | Always 1 — indicates gTelemetry is running |
| `gmod.telemetry.collection_errors` | Sum | Cumulative collector errors since server start |
| `gmod.telemetry.send_failures` | Sum | Cumulative HTTP send failures since server start |

### Players (`sv_players.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.players.count` | Gauge | — | Connected player count |
| `gmod.players.bots` | Gauge | — | Connected bot count |
| `gmod.players.ping` | Gauge | `player.name`, `player.steam_id` | Per-player ping (ms) |
| `gmod.players.ping_avg` | Gauge | — | Average ping across humans |
| `gmod.players.client_fps` | Gauge | `player.name`, `player.steam_id` | Client-reported FPS |
| `gmod.players.kills` | Sum | `player.name`, `player.steam_id` | Cumulative kills |
| `gmod.players.deaths` | Sum | `player.name`, `player.steam_id` | Cumulative deaths |
| `gmod.players.connection_time` | Gauge | `player.name`, `player.steam_id` | Time connected (s) |
| `gmod.players.load_time` | Gauge | `player.name`, `player.steam_id` | Connect-to-ready time (s). `-1` if client never reported ready within 120s |

### Entities (`sv_entities.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.entities.total` | Gauge | — | Total entity count |
| `gmod.entities.props` | Gauge | — | Prop count |
| `gmod.entities.ragdolls` | Gauge | — | Ragdoll count |
| `gmod.entities.npcs` | Gauge | — | NPC count |
| `gmod.entities.players` | Gauge | — | Player entity count |
| `gmod.entities.weapons` | Gauge | — | Weapon count |
| `gmod.entities.vehicles` | Gauge | — | Vehicle count |
| `gmod.entities.doors` | Gauge | — | Door count |
| `gmod.entities.scripted_ents` | Gauge | — | Scripted entities (SENTs) |
| `gmod.entities.constraints` | Gauge | — | Constraint/rope/hydraulic count |
| `gmod.entities.effects` | Gauge | — | Effect entity count |
| `gmod.physics.objects` | Gauge | — | Entities with an active physics object |
| `gmod.entities.owned_by_player` | Gauge | `player.name`, `player.steam_id`, `entity.type`, `entity.class` | Entities owned per player, grouped by type |

### Network (`sv_network.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.network.net_messages_out` | Sum | — | Net messages sent by server |
| `gmod.network.net_messages_in` | Sum | — | Net messages received by server |
| `gmod.network.messages_out_details` | Sum | `net.message` | Per-message-name sent breakdown |
| `gmod.network.messages_in_details` | Sum | `net.message` | Per-message-name received breakdown |
| `gmod.network.active_receivers` | Gauge | — | Total registered net message receivers |
| `gmod.network.packet_loss_avg` | Gauge | — | Average packet loss (%) |
| `gmod.network.packet_loss` | Gauge | `player.name`, `player.steam_id` | Per-player packet loss (%) |

### Hooks & Errors (`sv_hooks.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.hooks.count` | Gauge | — | Total registered hooks |
| `gmod.hooks.think_total` | Sum | — | Cumulative Think hook executions |
| `gmod.hooks.tick_total` | Sum | — | Cumulative Tick hook executions |
| `gmod.hooks.think_time` | Gauge | — | Time spent in Think hooks last frame (s) |
| `gmod.hooks.tick_time` | Gauge | — | Time spent in Tick hooks last tick (s) |
| `gmod.lua.errors` | Sum | — | Cumulative Lua error count |
| `gmod.hooks.by_event` | Gauge | `hook.event` | Hooks per event type (top 20) |

### Map & Server Info (`sv_map.lua`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.server.info` | Gauge | `server.map`, `server.gamemode`, `server.hostname`, `server.ip` | Server info (always 1) |
| `gmod.map.changes` | Sum | — | Map change count |

### Chat & Admin (`sv_chat.lua`)

| Metric | Type | Description |
|--------|------|-------------|
| `gmod.chat.messages` | Sum | Total chat messages |
| `gmod.admin.commands` | Sum | Admin commands executed |

### DarkRP Economy (`sv_darkrp.lua`)

*Only available when DarkRP is detected.*

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gmod.darkrp.money_total` | Gauge | — | Total money in circulation |
| `gmod.darkrp.money_avg` | Gauge | — | Average money per player |
| `gmod.darkrp.job_count` | Gauge | `darkrp.job` | Players per job |
| `gmod.darkrp.props_per_player` | Gauge | `player.name`, `player.steam_id` | Props per player |
| `gmod.darkrp.wanted_count` | Gauge | — | Wanted players |
| `gmod.darkrp.arrested_count` | Gauge | — | Arrested players |
| `gmod.darkrp.money_per_player` | Gauge | `player.name`, `player.steam_id` | Money per player |

## Log Events Reference (`sv_log_events.lua`)

*Disabled by default — set `gtelemetry_log_enabled 1` to activate. No hooks are registered until enabled.*

| Event | Severity | Body format | Attributes |
|-------|----------|-------------|------------|
| Chat message | INFO | `[TEAM] [PlayerName] message` | `log.source="chat"` |
| Player join | INFO | `PlayerName (STEAM_0:0:xxx) connected` | `log.source="player"`, `log.event="connect"` |
| Player leave | INFO | `PlayerName (STEAM_0:0:xxx) disconnected` | `log.source="player"`, `log.event="disconnect"` |
| Player death | INFO | `Victim was killed by Attacker with Weapon` | `log.source="player"`, `log.event="death"` |
| Lua error | ERROR | `[source] error message` + stack trace | `log.source="error"`, `log.realm` |
| Admin (ULX) | INFO | `[Admin/ULX] Player ran: cmd args` | `log.source="admin"`, `admin.mod="ulx"` |
| Admin (SAM) | INFO | `[Admin/SAM] Player ran: cmd args` | `log.source="admin"`, `admin.mod="sam"` |
| Admin (FAdmin) | INFO | `[Admin/FAdmin] Player ran: cmd args` | `log.source="admin"`, `admin.mod="fadmin"` |
| Map change | INFO | `Map changed: OLD_MAP -> NEW_MAP` | `log.source="system"`, `log.event="map_change"` |
| Server start | INFO | `Server started — hostname, map, gamemode, version` | `log.source="system"`, `log.event="server_start"` |
| Server shutdown | WARN | `Server shutting down` | `log.source="system"`, `log.event="server_stop"` |

Player names and Steam IDs appear **only in the log body**, never as indexed Loki labels, to prevent high cardinality.

### Resource attributes

Every log batch includes these resource-level attributes (same as metrics):
- `service.name`, `service.version`, `host.name`, `gmod.map`, `gmod.gamemode`

## Troubleshooting

### Metrics not reaching Alloy

1. **Check `-allowlocalhttp`**: GMod blocks HTTP to private IPs by default. Ensure your server start script includes it.
2. **Check the endpoint**: Run `gtelemetry_debug 1` in the server console to see detailed logging. Verify the endpoint URL.
3. **Check Alloy is running**: Open `http://<alloy-host>:12345` in a browser.
4. **Firewall**: Ensure port 4318 is open between your GMod server and Alloy.

### Logs not reaching Loki

1. **Check `gtelemetry_log_enabled 1`**: Log collection is disabled by default.
2. **Check the endpoint**: Default is `http://localhost:4318/v1/logs`. Run `gtelemetry_debug 1` to see flush activity.
3. **Alloy configuration**: Ensure your OTLP receiver routes logs to a Loki pipeline (see [Backend Setup](#lokiexperimental-log-pipeline)).
4. **Buffer overflow**: Increase `gtelemetry_log_buffer_size` if the server produces many events. Dropped logs are tracked in the health metric.

### DarkRP metrics not appearing

- DarkRP must be fully loaded before gTelemetry can detect it. If you see "DarkRP detected" in the console, it's working.
- Ensure `gtelemetry_darkrp 1`.
- Verify the gamemode exposes standard DarkRP functions.

### High CPU usage

- Increase `gtelemetry_interval` (e.g., `30`)
- Increase `gtelemetry_entities_interval` (e.g., `5` — scan every 5th cycle)
- On large servers (64+ players, 10k+ entities), the entity collector is the most expensive. `gtelemetry_entities_interval` helps most there.

### Authentication errors

- Set `gtelemetry_auth_token "your-token-here"` if your Alloy instance requires it.
- The ConVar is `FCVAR_PROTECTED` — it won't appear in server info queries.

## License

MIT License — See [LICENSE](../LICENSE) for details.
