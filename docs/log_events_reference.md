# Log Events Reference

*Disabled by default — set `gtelemetry_log_enabled 1` to activate. No hooks are registered until enabled.*

## Core log collectors (`gtelemetry_log_blogs_mode = "off"`)

Uses `sv_log_events.lua` — hooks 28 events directly via `hook.Add()`.

| Event | Severity | Body format | Attributes |
|-------|----------|-------------|------------|
| Chat message | INFO | `[TEAM] [PlayerName] message` | `log.source="chat"` |
| Player join | INFO | `PlayerName (SID) connected` | `log.source="player"`, `log.event="connect"` |
| Player leave | INFO | `PlayerName (SID) disconnected` | `log.source="player"`, `log.event="disconnect"` |
| Player death | INFO | `Victim was killed by Attacker with weapon` | `log.source="player"`, `log.event="death"` |
| Player hurt | INFO | `Attacker dealt X damage to Victim` | `log.source="combat"`, `log.event="hurt"` |
| Team change | INFO | `Player joined Team (from OldTeam)` | `log.source="player"`, `log.event="team_change"` |
| Vehicle enter | INFO | `Player entered vehicle_class` | `log.source="vehicle"`, `log.event="enter"` |
| Vehicle exit | INFO | `Player exited vehicle_class` | `log.source="vehicle"`, `log.event="exit"` |
| Lua error | ERROR | `[source] error message` + stack trace | `log.source="error"`, `log.realm` |
| Admin (ULX) | INFO | `[Admin/ULX] Player ran: cmd args` | `log.source="admin"`, `admin.mod="ulx"` |
| Admin (SAM) | INFO | `[Admin/SAM] Player ran: cmd args` | `log.source="admin"`, `admin.mod="sam"` |
| Admin (FAdmin) | INFO | `[Admin/FAdmin] Player ran: cmd args` | `log.source="admin"`, `admin.mod="fadmin"` |
| Admin (xAdmin) | INFO | `[Admin/xAdmin] Player ran: cmd args` | `log.source="admin"`, `admin.mod="xadmin"` |
| Prop spawned ¹ | INFO | `[Prop] Player spawned model` | `log.source="spawn"`, `spawn.type="prop"` |
| Vehicle spawned ¹ | INFO | `[Vehicle] Player spawned class` | `log.source="spawn"`, `spawn.type="vehicle"` |
| NPC spawned ¹ | INFO | `[NPC] Player spawned class` | `log.source="spawn"`, `spawn.type="npc"` |
| SENT spawned ¹ | INFO | `[SENT] Player spawned class` | `log.source="spawn"`, `spawn.type="sent"` |
| SWEP spawned ¹ | INFO | `[SWEP] Player spawned class` | `log.source="spawn"`, `spawn.type="swep"` |
| Ragdoll spawned ¹ | INFO | `[Ragdoll] Player spawned model` | `log.source="spawn"`, `spawn.type="ragdoll"` |
| Effect spawned ¹ | INFO | `[Effect] Player spawned model` | `log.source="spawn"`, `spawn.type="effect"` |
| Item pickup ¹ | INFO | `Player picked up class` | `log.source="item"`, `log.event="pickup"` |
| Weapon drop ¹ | INFO | `Player dropped class` | `log.source="item"`, `log.event="drop"` |
| Map change | INFO | `Map changed: OLD -> NEW` | `log.source="system"`, `log.event="map_change"` |
| Gamemode change | INFO | `Gamemode loaded: name` | `log.source="system"`, `log.event="gamemode_change"` |
| Server start | INFO | `Server started — hostname, map, gamemode, version` | `log.source="system"`, `log.event="server_start"` |
| Server shutdown | WARN | `Server shutting down` | `log.source="system"`, `log.event="server_stop"` |

¹ Requires `gtelemetry_log_spawn 1` (default 0). Disabled by default to avoid noise on sandbox servers.

Player names and Steam IDs appear **only in the log body**, never as indexed Loki labels, to prevent high cardinality.

## Resource attributes

Every log batch includes these resource-level attributes (same as metrics):
- `service.name`, `service.version`, `host.name`, `gmod.map`, `gmod.gamemode`

---

## bLogs bridge (`gtelemetry_log_blogs_mode = "replace"`)

Registers as a `GAS.Logging` module via `MODULE:Hook()`. Same event coverage and format as the core collectors above, but hooks go through bLogs' module API. Requires bLogs (Billy's Logs) and GmodAdminSuite to be installed.

## bLogs interceptor (`gtelemetry_log_blogs_mode = "intercept"`)

Wraps `LogPhrase`/`Phrase` on the GAS module metatable to capture ALL bLogs module output. No event-specific hooks needed.

| Attribute | Description | Source |
|---|---|---|
| `log.source="blogs"` | Identifies logs from bLogs interception | Fixed |
| `blogs.category` | bLogs module category (e.g. `"SAM"`, `"DarkRP"`) | `self.Category` |
| `blogs.module` | bLogs module name (e.g. `"Commands"`) | `self.Name` |
| `blogs.phrase` | Phrase key (e.g. `"command_used"`) | First arg to `LogPhrase` |

Body format: `[bLogs/Category/Module] phraseKey: formatted arg 1 | arg 2 | ...`

## bLogs hybrid (`gtelemetry_log_blogs_mode = "hybrid"`)

Runs both MODULE:Hook (with `log.source` specific to each event) and LogPhrase interceptor (with `log.source="blogs"`). Common events are captured twice but distinguishable by `log.source`. Provides maximum coverage at the cost of some duplicate log entries.
