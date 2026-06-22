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

## Architecture

- Global `GTelemetry` namespace; collectors register at `GTelemetry.Collectors.<Name>`
- Each collector implements `Init()` (lazy) and `Collect()` → returns list of OTLP metric objects
- Lazy-init pattern: `if not MakeGauge then Init() end` at top of `Collect()`
- `GTelemetry.OTLP.CollectAndSend()` iterates all collectors via `pcall`, builds OTLP JSON, sends via GMod's `HTTP()`
- Default endpoint: `http://localhost:4318/v1/metrics`
- ~50 metrics, all prefixed `gmod.`
- Config via ConVars (`gtelemetry_*`) — no config files
- 8 collectors: Server, Players, Entities, Network, Hooks, Map, Chat, DarkRP

## No standard dev tooling

No package.json, test framework, linter, typechecker, or CI.
Deploy by copying the addon to `garrysmod/addons/` and restarting the server.

## GLua reference

`https://samuelmaddock.github.io/glua-docs/` (also referenced in `.agents/rules/fuente.md`)

## Repo conventions

- `local` caching of frequently-used globals at module top
- Collectors use `pcall(collector.Collect)` for error isolation
- Cumulative counters track `_startTimeNano` and use `MakeCumulativeDataPoint`
- Client FPS sent via `net` library (`GTelemetry_ClientData` message)
- DarkRP auto-detected via `DarkRP.getPhrase`; metrics gated by `gtelemetry_darkrp`
- Network collector wraps `net.Start` / `net.Receive` to count messages
- Server info carried as label-only metric (`gmod.server.info` = always 1)
