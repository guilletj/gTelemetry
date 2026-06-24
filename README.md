# gTelemetry — GMod Telemetry

A Garry's Mod server monitoring addon that exports telemetry metrics to **Grafana** via **Grafana Alloy** using the **OpenTelemetry (OTLP/HTTP JSON)** protocol.

Monitor your GMod server's performance, players, entities, network, Lua errors, and more — all from beautiful Grafana dashboards.

## Architecture

```
┌─────────────────────┐  HTTP POST (OTLP/JSON)  ┌─────────────────────┐
│    GMod Server      │  ─────────────────────> │   Grafana Alloy     │
│  ┌───────────────┐  │   :4318/v1/metrics      │  otelcol receiver   │
│  │  gTelemetry   │  │                         └──────────┬──────────┘
│  │    (Lua)      │  │                                    │
│  └───────────────┘  │                         ┌──────────┴──────────┐
│  ┌───────────────┐  │                         │                     │
│  │ Client module │  │                    ┌────┴─────┐         ┌─────┴────┐
│  │ (FPS data)    │  │                    │Prometheus│         │ InfluxDB │
│  └───────────────┘  │                    └────┬─────┘         └─────┬────┘
└─────────────────────┘                         └──────────┬──────────┘
                                                     ┌─────┴─────┐
                                                     │  Grafana  │
                                                     └───────────┘
```

## Features

- **~59 metrics** across 8 collectors
- **Zero dependencies** — uses native GMod `HTTP()` function
- **OTLP standard** — compatible with any OpenTelemetry-compatible backend
- **DarkRP auto-detection** — economic metrics load automatically when DarkRP is present
- **Client FPS tracking** — collects client performance data via net library
- **Admin mod detection** — automatically hooks into ULX, SAM, and FAdmin for command tracking
- **Entity ownership breakdown** — per-player entity counts grouped by type (configurable)
- **Network message details** — per-message-name breakdown (configurable, high-cardinality gated)
- **Configurable** — all settings via server ConVars, runtime reconfiguration without restart
- **Late-init support** — works even if loaded after map start (e.g., via `lua_openscript`)
- **Graceful shutdown** — sends final metrics push on server shutdown
- **Lightweight** — minimal performance impact, async HTTP sends, error-isolated collectors, configurable entity scan interval
- **Resilient** — exponential backoff on HTTP failures (up to 2 minutes), health metrics for pipeline monitoring
- **Alert-ready** — includes [ready-to-use Grafana alert rules](docs/alert_rules.md) for anomaly detection with zero configuration

## Installation

1. Copy the entire addon folder to your GMod server's `addons` directory:
   ```
   garrysmod/addons/gTelemetry/
   ├── lua/
   │   ├── autorun/
   │   │   ├── server/gtelemetry_init.lua
   │   │   └── client/cl_gtelemetry.lua
   │   └── gtelemetry/
   │       ├── sv_config.lua
   │       ├── sv_otlp.lua
   │       └── collectors/
   │           ├── sv_server.lua
   │           ├── sv_players.lua
   │           ├── sv_entities.lua
   │           ├── sv_network.lua
   │           ├── sv_hooks.lua
   │           ├── sv_map.lua
   │           ├── sv_chat.lua
   │           └── sv_darkrp.lua
   └── README.md
   ```

2. **Required:** Start your server with the `-allowlocalhttp` launch parameter to allow HTTP requests to local/private IP addresses:
   ```
   srcds.exe -game garrysmod +gamemode sandbox +map gm_construct -allowlocalhttp
   ```

3. Restart the server or run `lua_openscript autorun/server/gtelemetry_init.lua` in the console.

## Configuration

All configuration is done via server ConVars, either in `server.cfg` or the server console.

| ConVar | Default | Description |
|---|---|---|
| `gtelemetry_enabled` | `1` | Master enable/disable switch |
| `gtelemetry_endpoint` | `http://localhost:4318/v1/metrics` | Alloy OTLP HTTP endpoint URL |
| `gtelemetry_interval` | `10` | Collection/push interval in seconds (1-300) |
| `gtelemetry_service_name` | `gmod-server` | OTLP service.name attribute (identifies this server in Grafana) |
| `gtelemetry_auth_token` | *(empty)* | Optional Bearer token for Alloy authentication |
| `gtelemetry_debug` | `0` | Enable verbose debug logging to server console |
| `gtelemetry_darkrp` | `1` | Enable DarkRP economic metrics (still requires DarkRP to be installed) |
| `gtelemetry_entities_per_player` | `1` | Enable per-player entity ownership breakdown (high cardinality) |
| `gtelemetry_entities_interval` | `1` | Collect entity metrics every N cycles (1 = every cycle, 2 = every other, etc.). Higher values reduce CPU on large maps |
| `gtelemetry_network_details` | `0` | Enable per-message-name net message breakdown (high cardinality) |
| `gtelemetry_version` | `1.0.0` | Version info (replicated to clients) |

### How intervals work

gTelemetry uses a **3-level pipeline** — each level has its own timing:

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
│  At 5, entities are scanned every 5th cycle (every 50s   │
│  if gtelemetry_interval is 10).                          │
└──────────────────────────────┬───────────────────────────┘
                               │
┌─ LEVEL 3: Export to Alloy ───────────────────────────────┐
│  gtelemetry_interval (default 10s):                      │
│  The same timer. After collecting, the payload is built  │
│  and sent via HTTP POST. This decides how often data     │
│  arrives in Prometheus / Grafana.                        │
└──────────────────────────────────────────────────────────┘
```

Key points:
- **gtelemetry_interval** = both the sampling trigger AND the export interval. Data reaches Prometheus at this rate.
- **gtelemetry_entities_interval** = skip N-1 cycles between entity scans to reduce CPU. Only affects entity metrics.
- **Client FPS** is sent every 5s regardless of gtelemetry_interval. The server uses the last received value on each collect cycle.
- All metrics use the collection timestamp (not the measurement timestamp). This is standard for Prometheus gauges and does not affect rate calculations.

### Example server.cfg

```
// gTelemetry configuration
gtelemetry_enabled 1
gtelemetry_endpoint "http://192.168.1.100:4318/v1/metrics"
gtelemetry_interval 15
gtelemetry_service_name "my-darkrp-server"
gtelemetry_debug 0
```

## Setting Up Grafana Alloy

### 1. Install Grafana Alloy

Follow the [official Alloy installation guide](https://grafana.com/docs/alloy/latest/get-started/install/) for your platform.

### 2. Configure Alloy

Use the example configuration in `docs/alloy_example.hcl` as a starting point:

```hcl
// Receive OTLP metrics from gTelemetry
otelcol.receiver.otlp "gmod" {
    http {
        endpoint = "0.0.0.0:4318"
    }
    output {
        metrics = [otelcol.processor.batch.default.input]
    }
}

// Batch before exporting
otelcol.processor.batch "default" {
    timeout = "5s"
    output {
        metrics = [otelcol.exporter.prometheus.default.input]
    }
}

// Export to Prometheus
otelcol.exporter.prometheus "default" {
    forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
    endpoint {
        url = "http://localhost:9090/api/v1/write"
    }
}
```

### 3. Run Alloy

```bash
alloy run config.alloy
```

Verify Alloy is receiving data at `http://localhost:12345` (Alloy's built-in UI).

### 4. Set Up Grafana

1. Add your Prometheus or InfluxDB as a data source in Grafana
2. Create dashboards using the metrics listed below
3. All metrics are prefixed with `gmod.` for easy filtering
4. See [`docs/alert_rules.md`](docs/alert_rules.md) for ready-to-use alert rules — copy-paste PromQL expressions for server overload, entity explosions, memory leaks, Lua errors, and more
5. See [`docs/discord_templates.md`](docs/discord_templates.md) for Discord notification templates — color-coded embeds with server, map, and value fields

## Metrics Reference

### Server Performance (`sv_server.lua`)

| Metric | Type | Description |
|---|---|---|
| `gmod.server.tickrate` | Gauge | Configured server tick rate (Hz) |
| `gmod.server.tick_interval` | Gauge | Time between server ticks (seconds) |
| `gmod.server.frametime` | Gauge | Actual server frame time (seconds) |
| `gmod.server.fps` | Gauge | Server frames per second |
| `gmod.server.lua_memory` | Gauge | Lua state memory usage (bytes) |
| `gmod.server.uptime` | Gauge | Server uptime since map load (seconds) |
| `gmod.server.max_players` | Gauge | Maximum player slots |
| `gmod.telemetry.active` | Gauge | Indicates gTelemetry is active and collecting (always 1) |
| `gmod.telemetry.collection_errors` | Sum | Cumulative number of collector errors since server start |
| `gmod.telemetry.send_failures` | Sum | Cumulative number of HTTP send failures since server start |
| `gmod.server.collection_duration` | Gauge | Time spent collecting and sending metrics in the last cycle (seconds) |
| `gmod.server.tick_duration` | Gauge | Ratio of frameTime to tickInterval — indicates server load (> 1.0 means server can't keep up) |

### Players (`sv_players.lua`)

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.players.count` | Gauge | — | Connected player count |
| `gmod.players.bots` | Gauge | — | Connected bot count |
| `gmod.players.ping` | Gauge | `player.name`, `player.steam_id` | Per-player ping (ms) |
| `gmod.players.ping_avg` | Gauge | — | Average ping across humans |
| `gmod.players.client_fps` | Gauge | `player.name`, `player.steam_id` | Client-reported FPS |
| `gmod.players.kills` | Sum | `player.name`, `player.steam_id` | Cumulative kills |
| `gmod.players.deaths` | Sum | `player.name`, `player.steam_id` | Cumulative deaths |
| `gmod.players.connection_time` | Gauge | `player.name`, `player.steam_id` | Time connected (seconds) |
| `gmod.players.load_time` | Gauge | `player.name`, `player.steam_id` | Time from connect to client fully loaded (seconds). `-1` if client never reported ready within 120s timeout |

### Entities (`sv_entities.lua`)

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.entities.total` | Gauge | — | Total entity count |
| `gmod.entities.props` | Gauge | — | Prop entities |
| `gmod.entities.ragdolls` | Gauge | — | Ragdoll entities |
| `gmod.entities.npcs` | Gauge | — | NPC entities |
| `gmod.entities.players` | Gauge | — | Player entities |
| `gmod.entities.weapons` | Gauge | — | Weapon entities |
| `gmod.entities.vehicles` | Gauge | — | Vehicle entities |
| `gmod.entities.doors` | Gauge | — | Door entities |
| `gmod.entities.scripted_ents` | Gauge | — | Scripted entities (SENTs) |
| `gmod.entities.constraints` | Gauge | — | Constraint/rope/hydraulic entities |
| `gmod.entities.effects` | Gauge | — | Effect entities |
| `gmod.physics.objects` | Gauge | — | Entities with an active physics object |
| `gmod.entities.owned_by_player` | Gauge | `player.name`, `player.steam_id`, `entity.type`, `entity.class` | Entities owned per player, grouped by type |

### Network (`sv_network.lua`)

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.network.net_messages_out` | Sum | — | Net messages sent by server |
| `gmod.network.net_messages_in` | Sum | — | Net messages received by server |
| `gmod.network.messages_out_details` | Sum | `net.message` | Net messages sent per message name |
| `gmod.network.messages_in_details` | Sum | `net.message` | Net messages received per message name |
| `gmod.network.active_receivers` | Gauge | — | Total registered net message receivers |
| `gmod.network.packet_loss_avg` | Gauge | — | Average packet loss (%) |
| `gmod.network.packet_loss` | Gauge | `player.name`, `player.steam_id` | Per-player packet loss (%) |

### Hooks & Errors (`sv_hooks.lua`)

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.hooks.count` | Gauge | — | Total registered hooks |
| `gmod.hooks.think_total` | Sum | — | Cumulative Think hook executions since server start |
| `gmod.hooks.tick_total` | Sum | — | Cumulative Tick hook executions since server start |
| `gmod.hooks.think_time` | Gauge | — | Time spent in Think hooks last frame (seconds) |
| `gmod.hooks.tick_time` | Gauge | — | Time spent in Tick hooks last tick (seconds) |
| `gmod.lua.errors` | Sum | — | Cumulative Lua error count |
| `gmod.hooks.by_event` | Gauge | `hook.event` | Hooks per event type |

### Map & Server Info (`sv_map.lua`)

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.server.info` | Gauge | `server.map`, `server.gamemode`, `server.hostname`, `server.ip` | Server info (always 1) |
| `gmod.map.changes` | Sum | — | Map change count |

### Chat & Admin (`sv_chat.lua`)

| Metric | Type | Description |
|---|---|---|
| `gmod.chat.messages` | Sum | Total chat messages |
| `gmod.admin.commands` | Sum | Admin commands executed |

### DarkRP Economy (`sv_darkrp.lua`)

*Only available when DarkRP is detected.*

| Metric | Type | Labels | Description |
|---|---|---|---|
| `gmod.darkrp.money_total` | Gauge | — | Total money in circulation |
| `gmod.darkrp.money_avg` | Gauge | — | Average money per player |
| `gmod.darkrp.job_count` | Gauge | `darkrp.job` | Players per job |
| `gmod.darkrp.props_per_player` | Gauge | `player.name`, `player.steam_id` | Props per player |
| `gmod.darkrp.wanted_count` | Gauge | — | Wanted players |
| `gmod.darkrp.arrested_count` | Gauge | — | Arrested players |
| `gmod.darkrp.money_per_player` | Gauge | `player.name`, `player.steam_id` | Money per player |

## Troubleshooting

### Metrics not reaching Alloy

1. **Check `-allowlocalhttp`**: GMod blocks HTTP requests to private IPs by default. Ensure your server start script includes `-allowlocalhttp`.

2. **Check the endpoint**: Run `gtelemetry_debug 1` in the server console to see detailed logging. Verify the endpoint URL matches your Alloy configuration.

3. **Check Alloy is running**: Open `http://<alloy-host>:12345` in a browser to access Alloy's built-in UI.

4. **Firewall**: Ensure port 4318 is open between your GMod server and Alloy.

### DarkRP metrics not appearing

- DarkRP must be fully loaded before gTelemetry can detect it. If you see "DarkRP detected" in the server console, it's working.
- Ensure `gtelemetry_darkrp` is set to `1`.
- Verify the gamemode is actually DarkRP (not a derivative that doesn't expose standard DarkRP functions).

### High CPU usage

- Increase the collection interval: `gtelemetry_interval 30`
- Reduce entity scan frequency: `gtelemetry_entities_interval 5` (scan only every 5th cycle)
- On very large servers (64+ players) with 10,000+ entities, the entity collector is the most expensive. Use `gtelemetry_entities_interval` to reduce its impact.

### Authentication errors

- If your Alloy instance requires authentication, set the Bearer token: `gtelemetry_auth_token "your-token-here"`
- The ConVar is marked as `FCVAR_PROTECTED` so it won't appear in server info queries.

## License

MIT License — Feel free to use, modify, and distribute. See [LICENSE](../LICENSE) for details.
