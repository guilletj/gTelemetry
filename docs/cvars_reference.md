# ConVar Reference

All configuration is managed via server ConVars. Set them in `server.cfg` or via console at runtime.

## Metrics ConVars

| ConVar | Default | FCVAR | Description |
|--------|---------|-------|-------------|
| `gtelemetry_enabled` | `1` | ARCHIVE | Master enable/disable switch for metric collection |
| `gtelemetry_endpoint` | `http://localhost:4318/v1/metrics` | ARCHIVE | Alloy OTLP HTTP endpoint URL for metrics |
| `gtelemetry_interval` | `10` | ARCHIVE | Collection and push interval in seconds (1-300) |
| `gtelemetry_service_name` | `gmod-server` | ARCHIVE | OTLP `service.name` resource attribute |
| `gtelemetry_auth_token` | *(empty)* | ARCHIVE, PROTECTED | Optional Bearer token for Alloy authentication |
| `gtelemetry_debug` | `0` | ARCHIVE | Enable verbose debug logging to server console |
| `gtelemetry_darkrp` | `1` | ARCHIVE | Enable DarkRP economic metrics (still requires DarkRP) |
| `gtelemetry_entities_per_player` | `1` | ARCHIVE | Enable per-player entity ownership breakdown (high cardinality) |
| `gtelemetry_entities_interval` | `1` | ARCHIVE | Collect entity metrics every N cycles (1 = every cycle) |
| `gtelemetry_network_details` | `0` | ARCHIVE | Enable per-message-name net message breakdown (high cardinality) |
| `gtelemetry_version` | `1.5.0` | ARCHIVE, REPLICATED | Version info (replicated to clients) |

## Log ConVars

| ConVar | Default | FCVAR | Description |
|--------|---------|-------|-------------|
| `gtelemetry_log_enabled` | `0` | ARCHIVE | Enable OTLP log collection and export to Loki via Alloy |
| `gtelemetry_log_endpoint` | `http://localhost:4318/v1/logs` | ARCHIVE | OTLP HTTP endpoint for log export |
| `gtelemetry_log_interval` | `10` | ARCHIVE | Log flush interval in seconds (1-300) |
| `gtelemetry_log_buffer_size` | `1000` | ARCHIVE | Maximum log entries buffered before dropping oldest (100-10000) |
| `gtelemetry_log_spawn` | `0` | ARCHIVE | Enable logging of spawn events (props, NPCs, SENTs, ragdolls, effects, item pickups). May be noisy on sandbox servers |
| `gtelemetry_log_blogs_mode` | `off` | ARCHIVE | bLogs integration mode: `off` (core collectors), `replace` (bLogs bridge via MODULE:Hook), `intercept` (LogPhrase wrapper), `hybrid` (both) |

## bLogs ConVar details

The `gtelemetry_log_blogs_mode` ConVar controls how gTelemetry integrates with Billy's Logs:

- **`off`** — Core log collectors (`sv_log_events.lua`) handle all event hooks directly via `hook.Add()`. No bLogs dependency.
- **`replace`** — Registers as a `GAS.Logging` module via `MODULE:Hook()` to capture events through bLogs' API. The core `sv_log_events.lua` is skipped. Requires bLogs + GmodAdminSuite.
- **`intercept`** — Wraps `LogPhrase`/`Phrase` on GAS module metatables to capture ALL bLogs module output. No event-specific hooks. The core `sv_log_events.lua` is used as fallback if bLogs is unavailable.
- **`hybrid`** — Runs both `replace` (event-specific MODULE:Hook) and `intercept` (catch-all LogPhrase wrapper). Common events may appear twice, distinguishable by `log.source` attribute. The core `sv_log_events.lua` is skipped.
