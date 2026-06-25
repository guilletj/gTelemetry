# gTelemetry — Bug Tracker

> Scratchpad de bugs encontrados. Formato: `[ ]` pendiente, `[x]` arreglado.

## Round 1 (commit 7f353d3) — 15 bugs fixed

- [x] **HIGH** — `prop_vehicle_*` classified as PROP (sv_entities.lua)
- [x] **HIGH** — GAS module orphan: `_cleanupModule` never removes module (sv_blogs.lua)
- [x] **HIGH** — Fallback interceptor `LogPhrase` permanently wrapped (sv_blogs.lua)
- [x] **HIGH** — `_prevMap` stored on `_module`, lost on cleanup (sv_blogs.lua)
- [x] **MEDIUM** — `table.remove(_logBuffer, 1)` is O(n) on overflow (sv_otlp_logs.lua)
- [x] **MEDIUM** — Wrong `Undo()` called when `blog_mode` changed since `Init` (sv_config.lua)
- [x] **MEDIUM** — No `pcall` around individual DarkRP player operations (sv_darkrp.lua)
- [x] **LOW** — Duplicate `prop_door` check (dead code) (sv_entities.lua)
- [x] **LOW** — No guard for `tickInterval = 0` (sv_server.lua)
- [x] **LOW** — Client ready signal is one-shot, lost on hot-reload (cl_gtelemetry.lua)
- [x] **LOW** — Same-map reloads not logged (sv_log_events.lua)
- [x] **LOW** — Invalid endpoint URLs delay recovery via backoff (sv_config.lua)
- [x] **LOW** — `CPPIGetOwner` existence check doesn't verify function type (sv_entities.lua)
- [x] **LOW** — AGENTS.md backoff docs wrong (AGENTS.md, gitignored)
- [x] **LOW** — `_mapChanges = 0` in Init discards first change (sv_map.lua)

## Round 2 (encontrados, NO fijados) — 9 bugs

- [ ] **HIGH** — Map `InitPostEntity` hook registered at module level, removed by `Undo()`, never re-registered by `Init()` → `_mapChanges` stagnates after toggle (sv_map.lua:27-31)
- [ ] **HIGH** — `_wrappedModules` restore writes the single stored original to BOTH `LogPhrase` and `Phrase`, corrupting one if module exposes both (sv_blogs.lua:345-361, 402-411)
- [ ] **MEDIUM** — `load_time = -1` documented as centinel but filtered out by `> 0` check; docs say -1 but metric omits it (sv_players.lua:190-191, docs/metrics_reference.md:34, docs/alert_rules.md)
- [ ] **MEDIUM** — bLogs shutdown hook (`gtelemetry_shutdown`) registered without priority via `_module:Hook`, runs AFTER main shutdown flush at default priority → "Server shutting down" log lost (sv_blogs.lua:239-241, gtelemetry_init.lua:181-194)
- [ ] **MEDIUM** — `net.Start("GTelemetry_RequestReady")` without `util.AddNetworkString` → server-side net message fails silently, client-ready retransmit broken (gtelemetry_init.lua:161, sv_players.lua:31-32)
- [ ] **LOW** — `_origPhrase` declared but never used (sv_blogs.lua:273)
- [ ] **LOW** — README says "exponential backoff up to 2 minutes", code uses 30s max (README.md:42)
- [ ] **LOW** — `docs/cvars_reference.md` lists `gtelemetry_version` default as `1.5.0`, actual is `1.5.6` (docs/cvars_reference.md:19)
- [ ] **LOW** — Redundant `or 0` in `totalMoney = totalMoney + (money or 0)` — `money` already defaults to 0 (sv_darkrp.lua:74)

## Round 3 (nueva búsqueda)

Pendiente de ejecutar.
