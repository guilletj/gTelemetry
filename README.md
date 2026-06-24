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
   │   ├── discord_templates.md
   │   ├── metrics_reference.md
   │   └── log_events_reference.md
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
| `gtelemetry_log_spawn` | `0` | Enable logging of spawn events (props, NPCs, SENTs, ragdolls, effects, item pickups). May be noisy on sandbox servers |

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
2. Use [`docs/alloy_example.hcl`](docs/alloy_example.hcl) as a starting point — metrics pipeline is active by default, Loki logs are an optional commented block
3. Run: `alloy run config.alloy`
4. Verify Alloy is receiving data at `http://localhost:12345` (Alloy's built-in UI)

### Grafana dashboards

1. Add Prometheus and/or Loki as data sources
2. Create dashboards using the metrics listed below (all prefixed `gmod.`)
3. See [`docs/alert_rules.md`](docs/alert_rules.md) for ready-to-use PromQL alert rules
4. See [`docs/discord_templates.md`](docs/discord_templates.md) for Discord notification embeds

## Metrics Reference

See [`docs/metrics_reference.md`](docs/metrics_reference.md) for the complete list of ~59 metrics across 8 collectors (server performance, players, entities, network, hooks, map, chat, DarkRP). All metrics are prefixed with `gmod.`.

## Log Events Reference (`sv_log_events.lua`)

See [`docs/log_events_reference.md`](docs/log_events_reference.md) for all 27 event types. Disabled by default — set `gtelemetry_log_enabled 1` to activate.`

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
