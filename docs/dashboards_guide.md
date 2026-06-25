# gTelemetry — Grafana Dashboards Guide

This document provides ready-to-use PromQL queries, visualization types, and unit settings for building Grafana dashboards with gTelemetry metrics.

---

## 1. Metric Naming in Prometheus

When Alloy converts OTLP metrics to Prometheus via `otelcol.exporter.prometheus`, metric names are transformed:

- **Dots** (`.`) become underscores (`_`)
- **Counters** (Sum + monotonic) get a `_total` suffix
- **Unit suffixes** are appended for recognized OTLP units (e.g., `_seconds`, `_milliseconds`, `_bytes`, `_hertz`, `_percent`)

> If `add_metric_suffixes` is enabled (default), the Prometheus name may differ from the OTLP name shown in `docs/metrics_reference.md`. Use the Prometheus name when writing queries.

### Quick naming examples

| OTLP name | Type | Unit | Prometheus name |
|-----------|------|------|-----------------|
| `gmod.server.frametime` | Gauge | `s` | `gmod_server_frametime_seconds` |
| `gmod.server.lua_memory` | Gauge | `By` | `gmod_server_lua_memory_bytes` |
| `gmod.players.ping` | Gauge | `ms` | `gmod_players_ping_milliseconds` |
| `gmod.players.kills` | Sum | `{kills}` | `gmod_players_kills_total` |
| `gmod.hooks.think_total` | Sum | `{calls}` | `gmod_hooks_think_total` (name already ends in `_total`) |
| `gmod.hooks.think_time` | Gauge | `s` | `gmod_hooks_think_time_seconds` |
| `gmod.chat.messages` | Sum | `{messages}` | `gmod_chat_messages_total` |
| `gmod.darkrp.money_total` | Gauge | `{currency}` | `gmod_darkrp_money_total` |
| `gmod.server.tickrate` | Gauge | `Hz` | `gmod_server_tickrate_hertz` |
| `gmod.network.packet_loss_avg` | Gauge | `%` | `gmod_network_packet_loss_avg_percent` |
| `gmod.network.packet_loss` | Gauge | `%` | `gmod_network_packet_loss_percent` |
| `gmod.telemetry.collection_errors` | Sum | `{errors}` | `gmod_telemetry_collection_errors_total` |

> **Tip**: Open Grafana's **Explore** tab and type `gmod_` to see all available metric names with their labels.

---

## 2. Unit Conversion Cheatsheet

Apply these in PromQL when the default unit is not convenient for your dashboard.

| Source unit | Prometheus suffix | To display as | PromQL transform |
|-------------|-------------------|---------------|------------------|
| hertz | `_hertz` | (already hertz) | — |
| percent | `_percent` | (already percent) | — |
| seconds | `_seconds` | milliseconds | `<metric> * 1000` |
| seconds | `_seconds` | minutes | `<metric> / 60` |
| seconds | `_seconds` | hours | `<metric> / 3600` |
| bytes | `_bytes` | kilobytes (KiB) | `<metric> / 1024` |
| bytes | `_bytes` | megabytes (MiB) | `<metric> / 1048576` |
| bytes | `_bytes` | gigabytes (GiB) | `<metric> / 1073741824` |

> Always set the panel **Unit** (e.g., `milliseconds`, `bytes(SI)`, `d(h:m:s)`) to match the transformed value.

---

## 3. Panel Presets

### 3.1 Server Performance

#### Server FPS
```promql
gmod_server_fps
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Unit | `{fps}` |
| Description | Current server FPS. Clamped to 1000 max. |

#### Frame Time
```promql
gmod_server_frametime_seconds * 1000
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Unit | `milliseconds` |
| Description | Time the last server frame took. Spikes indicate lag. |

#### Tick Duration (Load Indicator)
```promql
gmod_server_tick_duration
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Unit | `{ratio}` |
| Description | Ratio of frame time to tick interval. >1 means overloaded. |

#### Tick Rate
```promql
gmod_server_tickrate_hertz
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `hertz` |
| Description | Configured server tick rate (Hz). |

#### Lua Memory
```promql
gmod_server_lua_memory_bytes
```
| Property | Value |
|----------|-------|
| Visualization | Time series or Bar gauge |
| Unit | `bytes` |
| Description | Lua state memory usage. |

#### Server Uptime
```promql
gmod_server_uptime_seconds
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `dthms` (duration) |
| Description | Time since last map load. |

#### Collection Duration
```promql
gmod_server_collection_duration_seconds * 1000
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Unit | `milliseconds` |
| Description | Time spent in the last gTelemetry collection cycle. |

#### Telemetry Health
```promql
gmod_telemetry_active
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Description | Always 1. Use as an alert condition if it disappears. |

#### Collector / Send Errors
```promql
rate(gmod_telemetry_collection_errors_total[5m])
rate(gmod_telemetry_send_failures_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Description | Rate of collector failures and HTTP send failures. |

---

### 3.2 Players

#### Player Count
```promql
gmod_players_count
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Unit | `{players}` |
| Description | Total connected players (humans + bots). |

#### Bot Count
```promql
gmod_players_bots
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{players}` |

#### Average Ping
```promql
gmod_players_ping_avg_milliseconds
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Unit | `milliseconds` |
| Description | Average ping across all human players. |

#### Per-Player Ping
```promql
gmod_players_ping_milliseconds
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Unit | `milliseconds` |
| Description | Latency per player. Labels: `player.name`, `player.steam_id`. |

#### Client FPS
```promql
gmod_players_client_fps
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Unit | `{fps}` |
| Description | Client-reported FPS per player. Only emitted when data is received. |

#### Kills & Deaths
```promql
gmod_players_kills_total
gmod_players_deaths_total
```
| Property | Value |
|----------|-------|
| Visualization | Table or Time series |
| Description | Cumulative kills/deaths per player. Use `rate(...[5m])` for per-second rate. |

#### Connection Time
```promql
gmod_players_connection_time_seconds
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Unit | `s` |
| Description | Time since each player connected. |

#### Load Time
```promql
gmod_players_load_time_seconds
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Unit | `s` |
| Description | Time from connect to client fully loaded. `-1` if ClientReady never received within 120s. |

---

### 3.3 Entities

#### Total Entities
```promql
gmod_entities_total
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{entities}` |
| Description | Total entities in the world. |

#### Player Entities
```promql
gmod_entities_players
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{entities}` |

#### By Type + Owner (Stacked)
```promql
gmod_entities_by_type
```
| Property | Value |
|----------|-------|
| Visualization | Time series — Stacked bars or areas |
| Description | Entities grouped by `entity.type` (`prop`, `ragdoll`, `npc`, `weapon`, `vehicle`, `door`, `scripted_ent`, `constraint`, `effect`, `other`) and `entity.owner` (`world` or `player`). All type/owner combinations always emit (including 0). |

> **Filter examples:**
> - Ragdolls only: `gmod_entities_by_type{entity.type="ragdoll"}`
> - World-owned only: `gmod_entities_by_type{entity.owner="world"}`

#### Physics Objects
```promql
gmod_physics_objects
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{objects}` |
| Description | Entities with an active physics object. |

#### Per-Player Ownership
```promql
gmod_entities_owned_by_player
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Description | Entities owned per player, grouped by type. Labels: `player.name`, `player.steam_id`, `entity.type`. |

---

### 3.4 Network

#### Net Messages In/Out
```promql
rate(gmod_network_net_messages_in_total[5m])
rate(gmod_network_net_messages_out_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Description | Rate of net messages received/sent by the server. |

#### Net Messages by Name (Details)
```promql
rate(gmod_network_messages_out_details_total[5m])
rate(gmod_network_messages_in_details_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series or Table |
| Description | Per-message-name breakdown. Only when `gtelemetry_network_details` is enabled (high cardinality). Label: `net.message`. |

#### Active Net Receivers
```promql
gmod_network_active_receivers
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{receivers}` |
| Description | Number of registered net message receivers. |

#### Average Packet Loss
```promql
gmod_network_packet_loss_avg_percent
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Unit | `percent` |
| Description | Average packet loss across all human players (0 when none connected). |

#### Per-Player Packet Loss
```promql
gmod_network_packet_loss_percent
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Unit | `percent` |
| Description | Per-player packet loss (only when > 0). Labels: `player.name`, `player.steam_id`. |

---

### 3.5 Hooks & Errors

#### Think / Tick Hook Count
```promql
gmod_hooks_think_total
gmod_hooks_tick_total
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Description | Cumulative Think/Tick hook executions. Use `rate(...[5m])` for per-second rate. |

#### Think / Tick Execution Time
```promql
gmod_hooks_think_time_seconds * 1000
gmod_hooks_tick_time_seconds * 1000
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Unit | `milliseconds` |
| Description | Time spent executing hooks in the last frame/tick. Multiply by 1000 to convert seconds to milliseconds. |

#### Total Hooks Registered
```promql
gmod_hooks_count
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Unit | `{hooks}` |
| Description | Total number of registered hooks. |

#### Hooks by Event
```promql
gmod_hooks_by_event
```
| Property | Value |
|----------|-------|
| Visualization | Table or Bar gauge |
| Description | Top 20 hook events by hook count. Label: `hook.event`. |

#### Lua Errors
```promql
rate(gmod_lua_errors_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Description | Rate of Lua errors. |

---

### 3.6 Map & Server Info

#### Server Info
```promql
gmod_server_info
```
| Property | Value |
|----------|-------|
| Visualization | Stat (hide value, show labels) |
| Description | Always 1. Labels carry `server.map`, `server.gamemode`, `server.hostname`, `server.ip`. Useful as a data source for dashboard template variables. |

> **Template variable example** — PromQL query for a map selector:
> ```
> label_values(gmod_server_info, server.map)
> ```

#### Map Changes
```promql
gmod_map_changes_total
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Description | Number of map changes since server process start. |

---

### 3.7 Chat & Admin

#### Chat Message Rate
```promql
rate(gmod_chat_messages_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Description | Chat messages per second. |

#### Admin Command Rate
```promql
rate(gmod_admin_commands_total[5m])
```
| Property | Value |
|----------|-------|
| Visualization | Time series |
| Description | Admin commands per second. |

---

### 3.8 DarkRP Economy

*Only available when DarkRP is detected and `gtelemetry_darkrp` is enabled.*

#### Total Money in Circulation
```promql
gmod_darkrp_money_total
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Description | Total money across all players. |

#### Average Money Per Player
```promql
gmod_darkrp_money_avg
```
| Property | Value |
|----------|-------|
| Visualization | Stat or Time series |
| Description | Average money per player (0 when none connected). |

#### Money Per Player
```promql
gmod_darkrp_money_per_player
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Description | Money per individual player. Labels: `player.name`, `player.steam_id`. |

#### Job Distribution
```promql
gmod_darkrp_job_count
```
| Property | Value |
|----------|-------|
| Visualization | Table or Bar gauge |
| Description | Players per DarkRP job. Label: `darkrp.job`. |

#### Props Per Player
```promql
gmod_darkrp_props_per_player
```
| Property | Value |
|----------|-------|
| Visualization | Table |
| Description | Props spawned per player. Labels: `player.name`, `player.steam_id`. |

#### Wanted / Arrested
```promql
gmod_darkrp_wanted_count
gmod_darkrp_arrested_count
```
| Property | Value |
|----------|-------|
| Visualization | Stat |
| Description | Number of wanted/arrested players. |

---

## 4. Template Variables

Use dashboard template variables to make interactive filters.

| Variable | Type | PromQL query |
|----------|------|-------------|
| `$map` | Label values | `label_values(gmod_server_info, server.map)` |
| `$player` | Label values | `label_values(gmod_players_ping_milliseconds, player.name)` |
| `$entity_type` | Label values | `label_values(gmod_entities_by_type, entity.type)` |
| `$gamemode` | Label values | `label_values(gmod_server_info, server.gamemode)` |

---

## 5. Alert Rules Reference

See [`docs/alert_rules.md`](alert_rules.md) for ready-to-use Prometheus alerting rules compatible with these queries.
