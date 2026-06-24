# gTelemetry — Agent Guide

## What this is

Garry's Mod Lua addon for server telemetry (OTLP/HTTP JSON → Grafana via Alloy).
Uses GMod-specific globals (`HTTP`, `timer`, `hook`, `net`, `ents`, etc.) — not standard Lua.

## Essential setup requirement

GMod server **must** be started with `-allowlocalhttp` for HTTP to private/local IPs.

## File conventions

- `sv_` prefix → server-side files
- `cl_` prefix → client-side files
- Entry point: `lua/autorun/server/gtelemetry_init.lua` (loads all modules)
- Collectors: `lua/gtelemetry/collectors/sv_*.lua`
- Client file: `lua/autorun/client/cl_gtelemetry.lua` (sends FPS every 5s via net messages)

## Architecture

- Global `GTelemetry` namespace; collectors register at `GTelemetry.Collectors.<Name>`
- Each collector implements `Init()` (lazy) and `Collect()` → returns list of OTLP metric objects
- Lazy-init pattern: `if not MakeGauge then Init() end` at top of `Collect()`
- `GTelemetry.OTLP.CollectAndSend()` iterates all collectors via `pcall`, builds OTLP JSON, sends via GMod's `HTTP()`
- `GTelemetry.OTLP._cycleTimeNano` caches the cycle timestamp — all data points share one `GetTimeNano()` call
- Default endpoint: `http://localhost:4318/v1/metrics`
- ~59 metrics, all prefixed `gmod.`
- Config via ConVars (`gtelemetry_*`) — no config files
- 8 collectors: Server, Players, Entities, Network, Hooks, Map, Chat, DarkRP

## GMod threading model

- Single Lua state, everything synchronous
- No coroutines, no preemption — hooks and timers run sequentially in the same state
- `HTTP()` callbacks are asynchronous but return to the same state (no race conditions on shared data)
- `include()` re-executes the entire file, resetting all top-level `local` variables
- **Map changes do NOT reset the Lua state** — module-level `local` variables persist across maps

## No standard dev tooling

No package.json, test framework, linter, typechecker, or CI.
Deploy by copying the addon to `garrysmod/addons/` and restarting the server.

## GLua reference

`https://samuelmaddock.github.io/glua-docs/` (also referenced in `.agents/rules/fuente.md`)

## Repo conventions

- `local` caching of frequently-used globals at module top; only cache what won't affect metric precision (functions, single-cycle values, constants, properly-invalidated state)
- Collectors use `pcall(collector.Collect)` for error isolation
- Cumulative counters track `_startTimeNano` and use `MakeCumulativeDataPoint`
- Client FPS sent via `net` library (`GTelemetry_ClientData` message)
- DarkRP auto-detected via `DarkRP.getPhrase`; metrics gated by `gtelemetry_darkrp`
- Network collector wraps `net.Start` / `net.Receive` to count messages; `Undo()` restores originals
- Server info carried as label-only metric (`gmod.server.info` = always 1)
- Health counters (`GTelemetry.OTLP.CollectionErrors`, `.SendFailures`) exported from sv_otlp
- Entity collector can skip cycles via `gtelemetry_entities_interval` to reduce CPU; `_cycleCount` uses modulo wrap (`% (skipEvery * 1000)`) to prevent overflow
- Exponential backoff on HTTP failure (1s → 2s → 4s → … → 120s max)
- NaN/Inf guard pattern: `if value < math.huge and value > -math.huge` in `Attribute()` and `MakeDataPoint()`; falls back to `stringValue` / `asInt = "0"` for JSON safety
- `_cachedGamemode` captures `engine.ActiveGamemode()` once per session; invalidated via `gamemode.PostGamemodeLoaded` hook
- `_mapCountedThisLoad` guards external `CountChange()` calls only; the `InitPostEntity` hook increments freely since GMod fires it exactly once per map
- Gamemode health check: `engine.ActiveGamemode()` → `_cachedGamemode`, reset on `gamemode.PostGamemodeLoaded`
- Color-safe logging: `Warn()` nil-checks `Color()` before calling it
- Module-level caching of `string.match`, `string.StartWith`, `table.concat`, `math.floor`, `math.Round`, `math.min` for hot-path performance

## What NOT to cache

These look cacheable but are NOT safe — they change at runtime or depend on dynamic state:

- `hook.GetTable()` — hooks are registered/removed by addons at any time. Caching gives stale data.
- `player.GetAll()` — changes every cycle (players join/leave). Each collector stores it in `local players` inside `Collect()`.
- `gmod.GetGamemode()` / `engine.ActiveGamemode()` — only cache with explicit invalidation via `gamemode.PostGamemodeLoaded` hook.

## General cautions

- **`replaceAll` on strings inside code**: verify it does NOT replace inside `local` declarations. If the target string appears on both sides of an assignment (`local foo = foo`), the RHS gets corrupted. Always use targeted edits for declarations.
- **NaN/Inf**: Lua's division by zero produces `inf`, not an error. Always guard numerical metrics with `value < math.huge and value > -math.huge`.
- **`include()` resets locals**: if a file is `include()`d again (e.g., `lua_openscript`), all top-level `local` variables are re-initialized, resetting counters and state.
