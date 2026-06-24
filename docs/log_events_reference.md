# Log Events Reference

*Disabled by default — set `gtelemetry_log_enabled 1` to activate. No hooks are registered until enabled.*

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
