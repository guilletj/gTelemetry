# gTelemetry — Grafana Alert Rules

Ready-to-use Grafana alerts using the metrics gTelemetry already exports. No addon changes, no extra server-side processing.

## Prerequisites

- Prometheus data source configured in Grafana
- `gmod.*` metrics flowing from Alloy
- Recommended evaluation interval: `1m`
- Recommended `gtelemetry_interval`: `10s` to `30s`

## Grafana Alert Rule Settings Reference

Each alert below specifies these fields:

| Field | What it does | Recommendation |
|-------|-------------|----------------|
| `Severity` | Label attached to the alert | Used for routing and Discord embed color |
| `For` | How long the condition must be true before firing | Prevents **flapping** — transient spikes don't trigger notifications |
| `No data` | What happens when the metric stops arriving | `Alerting` for crash detection, `OK` for low-priority |
| `Auto-resolve` | When the alert recovers automatically | Always true — Grafana resolves when the condition is no longer met for the `For` duration |

After the `For` window expires:
- If still breaching → **fires** (notification sent)
- If no longer breaching → **resolves silently** (no extra delay)

---

## Table of Contents

1. [Server Performance](#1-server-performance)
2. [Players](#2-players)
3. [Entities](#3-entities)
4. [Errors & Addon Health](#4-errors--addon-health)
5. [DarkRP](#5-darkrp-optional)
6. [Network](#6-network)
7. [Dashboard Companion Panels](#7-dashboard-companion-panels)
8. [Technical Notes](#8-technical-notes)

---

## 1. Server Performance

### 1.1 Server Overloaded

Frame time exceeds tick interval — the server cannot keep up. Common causes: too many entities, heavy hooks, or poorly optimized addons.

```promql
gmod.server.tick_duration > 1
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `2m` |
| No data | Alerting |
| Summary | Server overloaded (tick_duration = {{ $value \| humanize }}) |
| Description | Frame time (`gmod.server.frametime`) exceeds tick interval (`gmod.server.tick_interval`). Server cannot keep up with configured tick rate. |
| Auto-resolve | `tick_duration <= 1` for 2m |

**Optimization**: Add `-tickrate 33` to your server start params if this fires often.

---

### 1.2 Server FPS Critically Low

```promql
gmod.server.fps < 20
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `1m` |
| No data | Alerting |
| Summary | Server FPS critically low ({{ $value \| humanize }}) |
| Description | Server is running at {{ $value }} FPS. Players will experience lag. |

**Optimization**: Correlate with `gmod.entities.total` and `gmod.physics.objects` to identify the cause.

---

### 1.3 Server FPS Degraded

```promql
gmod.server.fps < 30
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `3m` |
| No data | Alerting |
| Summary | Server FPS degraded ({{ $value \| humanize }}) |
| Description | Server FPS dropped to {{ $value }}. Investigate addons, entities, or physics load. |

**Optimization**: Use a higher `For` (3m) to ignore brief dips during map loads or entity-heavy events.

---

### 1.4 Possible Memory Leak

Detects rapid Lua memory growth over a short period.

```promql
delta(gmod.server.lua_memory[10m]) > 100 * 1024 * 1024
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `0m` |
| No data | OK |
| Summary | Possible Lua memory leak ({{ $value \| humanizeBytes }} in 10m) |
| Description | Lua memory grew by {{ $value \| humanizeBytes }} in the last 10 minutes. If sustained, this will crash the server. |

**Optimization**: Already rate-based (`delta[10m]`), so `For: 0m` is safe. Change `100MB` to `50MB` for tighter detection on small servers.

---

### 1.5 Lua Memory High

```promql
gmod.server.lua_memory > 500 * 1024 * 1024
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | Alerting |
| Summary | Lua memory high ({{ $value \| humanizeBytes }}) |
| Description | Lua memory at {{ $value \| humanizeBytes }}. GMod servers typically crash above 1-2 GB. |

**Optimization**: `For: 2m` prevents alerting on GC spikes that temporarily push memory up. If your server has many addons, lower the threshold to `300MB`.

---

### 1.6 Metrics Collection Lag

The telemetry addon itself is taking too long to collect and send.

```promql
gmod.server.collection_duration > 5
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Metrics collection taking too long ({{ $value }}s) |
| Description | The collection cycle took {{ $value }} seconds. Increase `gtelemetry_interval` or reduce entity scan frequency (`gtelemetry_entities_interval`). |

**Optimization**: If this fires, the entity collector is likely the bottleneck. Set `gtelemetry_entities_interval 5` to scan entities every 5th cycle.

---

## 2. Players

### 2.1 Server Empty

```promql
gmod.players.count == 0
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `5m` |
| No data | Alerting (crash detection) |
| Summary | Server is empty |
| Description | No players connected for at least 5 minutes. |
| Auto-resolve | `count > 0` |

**Optimization**: `For: 5m` avoids noise during server restarts. Create a **mute timing** in Grafana for known low-traffic hours.

---

### 2.2 Sudden Player Drop

Detects mass disconnects. More than 5 players leaving in 1 minute is anomalous.

```promql
delta(gmod.players.count[1m]) < -5
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `0m` |
| No data | OK |
| Summary | Sudden player drop ({{ $value \| abs }} in 1m) |
| Description | {{ $value \| abs }} players disconnected in the last minute. Possible crash, network issue, or server lag spike. |

**Optimization**: Already a delta — immediate firing is correct. No `For` needed. Use with 1.1 (Server Overloaded) to detect if lag caused players to leave.

---

### 2.3 Player Join Flood

```promql
delta(gmod.players.count[1m]) > 10
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `0m` |
| No data | OK |
| Summary | Player join flood ({{ $value }} in 1m) |
| Description | {{ $value }} players joined in the last minute. Verify it's not a bot attack. |

---

### 2.4 High Average Ping

```promql
gmod.players.ping_avg > 200
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `3m` |
| No data | OK |
| Summary | High average ping ({{ $value }}ms) |
| Description | Average ping across all players is {{ $value }}ms. Check server location, network, or upstream bandwidth. |

**Optimization**: `For: 3m` avoids false positives from a single high-ping player skewing the average. Adjust threshold down to `150` for competitive servers.

---

### 2.5 High Packet Loss

```promql
gmod.network.packet_loss_avg > 10
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | High packet loss ({{ $value }}%) |
| Description | Average packet loss is {{ $value }}%. Players will experience rubberbanding and disconnects. |

---

### 2.6 Many Players With Packet Loss

```promql
count(gmod.network.packet_loss > 10) > 2
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `2m` |
| No data | OK |
| Summary | {{ $value }} players with >10% packet loss |
| Description | Multiple players experiencing high packet loss. Network issue likely. |

---

### 2.7 Slow Client Load Time

Players taking too long to load may have slow workshop downloads. `gmod.players.load_time` reports `-1` if the client never sent the ready signal.

```promql
gmod.players.load_time > 60
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `0m` |
| No data | OK |
| Summary | Player load time > 60s ({{ $value }}s) |
| Description | Player {{ $labels.player_name }} ({{ $labels.player_steam_id }}) took {{ $value }}s to load. May indicate slow workshop download or addon issues. |

**Optimization**: Adjust threshold to `120` if your server has many workshop addons. This metric is per-player and fires once per connection — no `For` needed.

---

## 3. Entities

### 3.1 Entity Explosion

Sudden change in total entity count. Detects prop spam, dupe pastes, or mass cleanups.

```promql
abs(delta(gmod.entities.total[1m])) > 500
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `0m` |
| No data | OK |
| Summary | Entity count changed by {{ $value \| abs }} in 1m |
| Description | Total entities changed by {{ $value \| abs }} in one minute. Possible prop spam, dupe paste, or mass cleanup. |

**Optimization**: Delta-based — immediate firing is the point of this alert. Lower to `200` for tighter prop-spam detection on small servers.

---

### 3.2 Maximum Entities Warning

Source Engine has a hard limit of ~10000 entities (`game.MaxEntities()`). Approaching this limit risks crashes.

```promql
gmod.entities.total > 8000
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `1m` |
| No data | Alerting |
| Summary | Entity count critical ({{ $value }}) |
| Description | {{ $value }} entities in the world. Approaching the Source engine limit (~10000). |
| Auto-resolve | `total <= 8000` for 1m |

---

### 3.3 Entity Count Warning

```promql
gmod.entities.total > 5000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `3m` |
| No data | OK |
| Summary | High entity count ({{ $value }}) |
| Description | {{ $value }} entities. Performance may degrade. Investigate if growing. |

**Optimization**: `For: 3m` avoids alerting during brief entity spikes (e.g., map transitions when spawning entities).

---

### 3.4 Prop Spam

```promql
gmod.entities.by_type{entity.type="prop", entity.owner="player"} > 3000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Too many props ({{ $value }}) |
| Description | {{ $value }} props in the world. Excessive props cause server lag. Consider enforcing prop limits. |

---

### 3.5 Ragdoll Accumulation

Uncleaned ragdolls are a common cause of performance degradation over time.

```promql
gmod.entities.by_type{entity.type="ragdoll"} > 50
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `5m` |
| No data | OK |
| Summary | Ragdoll accumulation ({{ $value }}) |
| Description | {{ $value }} ragdolls. Consider auto-cleanup or lower `gmod_ragdoll_cleanup_time`. |

**Optimization**: `For: 5m` prevents alerting during fights where many ragdolls exist momentarily before cleanup.

---

### 3.6 Physics Object Overload

Entities with active physics are much more expensive than static ones.

```promql
gmod.physics.objects > 2000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Physics objects high ({{ $value }}) |
| Description | {{ $value }} physics objects. Physics simulation cost scales linearly. |

---

### 3.7 Constraint Overload

Too many constraints can destabilize the physics engine.

```promql
gmod.entities.by_type{entity.type="constraint"} > 1000
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `3m` |
| No data | OK |
| Summary | High constraint count ({{ $value }}) |
| Description | {{ $value }} constraints. May cause physics instability. |

---

## 4. Errors & Addon Health

### 4.1 Lua Error Spike

More than 5 errors per minute sustained indicates a broken addon or serious conflict.

```promql
rate(gmod.lua.errors[5m]) > 5
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `2m` |
| No data | OK |
| Summary | Lua error spike ({{ $value \| humanize }}/s) |
| Description | Lua errors are occurring at {{ $value }} per second. An addon is likely broken. Check server console for error stack traces. |
| Auto-resolve | `rate(...[5m]) <= 5` for 2m |

**Optimization**: `For: 2m` ensures the spike is sustained and not a one-off batch of errors from a map transition.

---

### 4.2 Lua Error Warning

```promql
rate(gmod.lua.errors[5m]) > 1
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `5m` |
| No data | OK |
| Summary | Lua errors detected ({{ $value \| humanize }}/s) |
| Description | Sustained Lua errors at {{ $value }}/s. Investigate before it escalates. |

**Optimization**: `For: 5m` catches slow-burn error accumulation. Lower to `2m` if you want faster detection.

---

### 4.3 Collector Failures

The addon is failing to collect metrics from some collectors. May indicate a wider server problem.

```promql
rate(gmod.telemetry.collection_errors[5m]) > 0
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Collector failures detected |
| Description | gTelemetry collectors are failing. Check server console with `gtelemetry_debug 1`. |

---

### 4.4 Send Failures (Alloy Down)

The addon cannot send metrics to Alloy. Alloy may be down, a firewall may be blocking the port, or the server lacks `-allowlocalhttp`.

```promql
rate(gmod.telemetry.send_failures[10m]) > 0
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `3m` |
| No data | OK |
| Summary | Metrics not reaching Alloy |
| Description | gTelemetry cannot send metrics. Verify Alloy is running, port 4318 is open, and the server has `-allowlocalhttp`. |
| Auto-resolve | When Alloy comes back and send succeeds for 3m |

**Optimization**: `For: 3m` gives Alloy time to restart during updates. The `[10m]` range already provides smoothing.

---

### 4.5 Telemetry Inactive

The addon stopped reporting. The server may have crashed or the addon broke.

```promql
absent(gmod.telemetry.active) == 1
```

| Field | Value |
|-------|-------|
| Severity | Critical |
| For | `0m` |
| No data | — (built-in, fires when data stops) |
| Summary | gTelemetry stopped reporting |
| Description | No telemetry data received for at least 2 evaluation intervals. The server may have crashed or the addon stopped working. |
| Auto-resolve | When `gmod.telemetry.active` reappears |

**Optimization**: `absent()` is the most efficient way to detect server crashes — no `For` needed, fires as soon as the evaluation interval expires without data.

---

### 4.6 Hook Count Anomaly

A sudden change in registered hooks indicates an addon was loaded or unloaded unexpectedly (e.g., `lua_openscript` reload).

```promql
abs(delta(gmod.hooks.count[5m])) > 50
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `0m` |
| No data | OK |
| Summary | Hook count changed by {{ $value \| abs }} |
| Description | {{ $value \| abs }} hooks added or removed. Possible addon reload or Lua script injection. |

**Optimization**: Immediate firing by design — hook changes are always interesting. Increase threshold to `100` if your server normally loads many addons.

---

## 5. DarkRP (optional)

Only applies when DarkRP is active and `gtelemetry_darkrp = 1`.

### 5.1 Economy Crash

Total money in circulation dropped abruptly. May be an admin reset or exploit.

```promql
delta(gmod.darkrp.money_total[5m]) < -100000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Economy dropped by {{ $value \| humanize }} in 5m |
| Description | Total money in circulation dropped by {{ $value \| abs }}. Could be admin reset or money exploit. |

---

### 5.2 Economy Hyperinflation

```promql
delta(gmod.darkrp.money_total[5m]) > 500000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Economy increased by {{ $value \| humanize }} in 5m |
| Description | Total money increased by {{ $value }} in 5 minutes. Possible money dupe or admin grant. |

---

### 5.3 Mass Arrest

```promql
gmod.darkrp.arrested_count > (gmod.players.count * 0.5)
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `1m` |
| No data | OK |
| Summary | Mass arrest ({{ $value }} players) |
| Description | Over half the server is arrested. May be a police raid event or an admin abusing arrest. |

---

### 5.4 Extreme Wealth Disparity

A player has significantly more money than average. Possible exploit or admin abuse.

```promql
max(gmod.darkrp.money_per_player) > avg(gmod.darkrp.money_per_player) * 10
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `2m` |
| No data | OK |
| Summary | Extreme wealth disparity detected |
| Description | A player has 10x the average money. Investigate for exploits. |

**Optimization**: Increase multiplier to `20` for larger servers to avoid false positives from naturally wealthy players.

---

## 6. Network

### 6.1 Net Message Flood

```promql
rate(gmod.network.net_messages_out[1m]) > 5000
```

| Field | Value |
|-------|-------|
| Severity | Warning |
| For | `2m` |
| No data | OK |
| Summary | Net message flood ({{ $value \| humanize }}/s) |
| Description | Server is sending {{ $value }} net messages per second. Possible addon spam or attack. |

---

### 6.2 Net Message In Rate Spike

```promql
rate(gmod.network.net_messages_in[1m]) > 1000
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `2m` |
| No data | OK |
| Summary | High incoming net message rate ({{ $value }}/s) |
| Description | Receiving {{ $value }} net messages/s from clients. Investigate if sustained. |

---

### 6.3 Map Change Detected

Not an anomaly — a useful reset marker.

```promql
increase(gmod.map.changes[1m]) > 0
```

| Field | Value |
|-------|-------|
| Severity | Info |
| For | `0m` |
| No data | OK |
| Summary | Map changed to {{ $labels.server_map }} |
| Description | Server changed maps. Useful as a reset marker for other alerts. |

---

## 7. Dashboard Companion Panels

### 7.1 Server Health Score

Combines key indicators into a single 0–100 score. Useful as a top-level panel.

```promql
(
  (gmod.server.fps > 30) * 0.25 +
  (gmod.server.tick_duration < 0.8) * 0.25 +
  (gmod.server.lua_memory < 300 * 1024 * 1024) * 0.25 +
  (rate(gmod.lua.errors[5m]) < 1) * 0.25
) * 100
```

---

### 7.2 Anomaly Correlation Panel

Multi-query panel showing FPS, tick_duration, Lua errors, and packet loss simultaneously.

```
// Four separate queries in one time-series panel:
// 1. gmod.server.fps
// 2. gmod.server.tick_duration
// 3. rate(gmod.lua.errors[5m])
// 4. gmod.network.packet_loss_avg
```

---

### 7.3 Entity Composition Over Time

Stacked area chart showing entity evolution.

```promql
{
  gmod.entities.by_type{entity.type="prop"},
  gmod.entities.by_type{entity.type="ragdoll"},
  gmod.entities.by_type{entity.type="npc"},
  gmod.entities.by_type{entity.type="weapon"},
  gmod.entities.by_type{entity.type="vehicle"},
  gmod.entities.by_type{entity.type="constraint"}
}
```

A sudden prop spike with a simultaneous FPS drop = confirmed prop spam.

---

### 7.4 Player Retention

Histogram or table panel.

```promql
gmod.players.connection_time
```

---

## 8. Technical Notes

### `rate()` vs `delta()` — when to use each

| Metric type | Example | Recommended | Why |
|-------------|---------|-------------|-----|
| **Sum** (cumulative) | `gmod.lua.errors` | `rate(...[5m])` | Prometheus calculates per-second increase |
| **Sum** (cumulative) | `gmod.lua.errors` | `increase(...[5m])` | Absolute value over the period |
| **Gauge** | `gmod.players.count` | `delta(...[1m])` | Absolute change between two points |
| **Gauge** | `gmod.server.lua_memory` | `delta(...[10m])` | How much it grew or shrank |

### Flapping prevention overview

| Technique | Applied in | Effect |
|-----------|-----------|--------|
| `For` | All alerts with `For > 0` | Condition must be true for N minutes |
| Rate/Delta range | `delta[10m]`, `rate[5m]` | Built-in smoothing over the window |
| `No data` → OK | Non-critical alerts | Prevents alerting during server restarts |

### Threshold Tuning

1. Review a week of historical data in Grafana
2. Identify the 95th percentile for each metric
3. Set thresholds at the 99th percentile, or 20–30% above p95

Example: if your p95 for `gmod.entities.total` is 3000, alert at 4000–4500.

### Mute timings

- Use Grafana **mute timings** for known maintenance windows
- `gmod.players.count == 0` should have a nighttime mute if the server is not 24/7

### Recommended evaluation intervals

| `gtelemetry_interval` | Evaluation group | `For` minimum |
|-----------------------|------------------|---------------|
| 10s (default) | 30s or 1m | 1m |
| 30s | 1m | 2m |
| 60s | 2m | 3m |

Rule of thumb: `evaluation >= gtelemetry_interval * 2`, `For >= evaluation * 2` for flapping-sensitive alerts.
