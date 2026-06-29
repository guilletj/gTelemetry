# gTelemetry — Discord Alert Templates

Go templating for Grafana 13+. Two approaches depending on how much control you need over the Discord embed.

## Prerequisites

- Grafana 13+ (Discord integration and Webhook/Custom Payload built-in)
- Discord webhook URL (Server Settings → Integrations → Webhooks → New Webhook)

## Shared: Notification Template Group

Both approaches use a Notification Template group. Create it once and reference the templates you need.

1. Go to **Alerts & IRM** → **Alerting** → **Notification configuration** → **Templates** tab
2. Click **+ New notification template group**
3. **Name**: `gTelemetry Discord`
4. Paste this block into the **Content** field and save:

```go
{{ define "gtelemetry.title" }}
  {{- if eq .Status "resolved" -}}
  ✅ [RECOVERED] {{ (index .Alerts 0).Annotations.summary }}
  {{- else -}}
    {{- $critical := false -}}
    {{- $info := false -}}
    {{- range .Alerts -}}
      {{- if eq (toLower .Labels.severity) "critical" -}}{{- $critical = true -}}{{- end -}}
      {{- if eq (toLower .Labels.severity) "info" -}}{{- $info = true -}}{{- end -}}
    {{- end -}}
    {{- if $critical -}}🚨{{- else if $info -}}ℹ️{{- else -}}⚠️{{- end }} [FIRING] {{ (index .Alerts 0).Annotations.summary }}
  {{- end -}}
{{ end -}}

{{ define "gtelemetry.duration" -}}
  {{- $dur := .EndsAt.Sub .StartsAt -}}
  {{- reReplaceAll "\\.\\d+s" "s" (printf "%v" $dur) -}}
{{ end -}}
```

---

## Approach A — Discord Native (simple)

The Discord integration gives you an embed with title + Grafana footer + URL, plus plain text above it.

### Contact point setup

1. Go to **Contact points** → **New contact point**
2. **Name**: `gTelemetry Discord` — **Integration**: Discord — **Discord URL**: your webhook URL
3. Toggle **Optional Discord settings** → **Use custom message**
4. Set:
   - **Title**: `{{ template "gtelemetry.title" . }}`
   - **Message Content**: `{{ template "gtelemetry.message" . }}`
5. Save

### Add to Notification Template group

Add this alongside `gtelemetry.title` and `gtelemetry.duration` in the same group:

```go
{{ define "gtelemetry.message" -}}
  {{- range $i, $alert := .Alerts -}}
  {{- if $i }}
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {{ end -}}
  {{ .Annotations.description }}
  {{- $server := index .Labels "service.name" -}}
  {{- if not $server }}{{ $server = index .Labels "service_name" }}{{ end -}}
  {{- if not $server }}{{ $server = "n/a" }}{{ end -}}
  {{- $host := index .Labels "host.name" -}}
  {{- if not $host }}{{ $host = index .Labels "host_name" }}{{ end -}}
  {{- if $host }}{{ $server = printf "%s (%s)" $server $host }}{{ end -}}
  {{- $map := index .Labels "gmod.map" -}}
  {{- if not $map }}{{ $map = index .Labels "gmod_map" }}{{ end -}}
  {{- if not $map }}{{ $map = index .Labels "server.map" }}{{ end -}}
  {{- if not $map }}{{ $map = index .Labels "server_map" }}{{ end -}}
  {{- $gm := index .Labels "gmod.gamemode" -}}
  {{- if not $gm }}{{ $gm = index .Labels "gmod_gamemode" }}{{ end -}}
  {{- if not $gm }}{{ $gm = index .Labels "server.gamemode" }}{{ end -}}
  {{- if not $gm }}{{ $gm = index .Labels "server_gamemode" }}{{ end -}}
  **Server:** {{ $server }}{{ if $map }} • **Map:** {{ $map }}{{ end }}{{ if $gm }} • **Gamemode:** {{ $gm }}{{ end }}
  {{- if eq $.Status "resolved" -}}
    {{- $dur := .EndsAt.Sub .StartsAt -}}
    {{- if gt $dur 0 -}}
      {{- $durStr := reReplaceAll "\\.\\d+s" "s" (printf "%v" $dur) -}}
      {{- if not (eq $durStr "0s") -}}
  **Duration:** {{ $durStr }}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- end -}}
{{ end }}
```

### How it looks (Discord Native)

```
Frame time (0.029s) exceeds tick interval (0.015s).
Server cannot keep up with configured tick rate.

Server: gmod-server (myserver.local) • Map: gm_construct • Gamemode: darkrp

╔══════════════════════════════════════╗
║ 🚨 [FIRING] Server Overloaded          ║  ← embed title
╠══════════════════════════════════════╣
║ Grafana v13                   🔗     ║  ← built-in footer + URL
╚══════════════════════════════════════╝
```

### Pros & cons

| Pro | Con |
|-----|-----|
| Minimal setup | Embed is fixed (no custom fields, no description in embed) |
| Uses Grafana's native Discord integration | Text content goes outside/before the embed |
| Works out of the box | |

---

## Approach B — Webhook + Custom Payload (full control)

Use a **Webhook contact point** pointed at the same Discord webhook URL, with **Custom Payload** to build the entire embed yourself.

### Contact point setup

1. Go to **Contact points** → **New contact point**
2. **Name**: `gTelemetry Discord Webhook` — **Integration**: Webhook
3. **URL**: your Discord webhook URL
4. **HTTP Method**: `POST`
5. In **Optional settings**, set:
   - **Max Alerts**: `10`
6. Toggle **Custom Payload** → **Payload Template**: `{{ template "gtelemetry.custom" . }}`
7. (Optional) Add **Payload Variables** if needed
8. Save

### Add to Notification Template group

Add these alongside `gtelemetry.title` and `gtelemetry.duration`:

```go
{{ define "gtelemetry.custom" -}}
  {{- $color := 15844367 -}}
  {{- $critical := false -}}
  {{- range .Alerts -}}
    {{- if eq (toLower .Labels.severity) "critical" -}}{{- $critical = true -}}{{- end -}}
    {{- if eq (toLower .Labels.severity) "info" -}}{{- $color = 5793266 -}}{{- end -}}
  {{- end -}}
  {{- if $critical -}}{{- $color = 15548997 -}}{{- end -}}
  {{- if eq .Status "resolved" -}}{{- $color = 5763719 -}}{{- end -}}
  {{ coll.Dict
    "embeds" (coll.Slice (coll.Dict
      "title" (tmpl.Inline `{{ template "gtelemetry.title" . }}` .)
      "color" $color
      "fields" (tmpl.Exec "gtelemetry.custom_fields" . | data.JSON)
      "timestamp" (index .Alerts 0).StartsAt
      "footer" (coll.Dict "text" "gTelemetry")
    ))
  | data.ToJSONPretty "  " }}
{{ end -}}

{{ define "gtelemetry.custom_fields" -}}
  {{- $fields := coll.Slice -}}
  {{- range .Alerts -}}
    {{- $fields = coll.Append (coll.Dict "name" .Annotations.summary "value" .Annotations.description "inline" false) $fields -}}
    {{- $server := index .Labels "service.name" -}}
    {{- if not $server }}{{ $server = index .Labels "service_name" }}{{ end -}}
    {{- if not $server }}{{ $server = "n/a" }}{{ end -}}
    {{- $host := index .Labels "host.name" -}}
    {{- if not $host }}{{ $host = index .Labels "host_name" }}{{ end -}}
    {{- if $host }}{{ $server = printf "%s (%s)" $server $host }}{{ end -}}
    {{- $map := index .Labels "gmod.map" -}}
    {{- if not $map }}{{ $map = index .Labels "gmod_map" }}{{ end -}}
    {{- if not $map }}{{ $map = index .Labels "server.map" }}{{ end -}}
    {{- if not $map }}{{ $map = index .Labels "server_map" }}{{ end -}}
    {{- $gm := index .Labels "gmod.gamemode" -}}
    {{- if not $gm }}{{ $gm = index .Labels "gmod_gamemode" }}{{ end -}}
    {{- if not $gm }}{{ $gm = index .Labels "server.gamemode" }}{{ end -}}
    {{- if not $gm }}{{ $gm = index .Labels "server_gamemode" }}{{ end -}}
    {{- $fields = coll.Append (coll.Dict "name" "Server" "value" $server "inline" true) $fields -}}
    {{- if $map -}}
      {{- $fields = coll.Append (coll.Dict "name" "Map" "value" $map "inline" true) $fields -}}
    {{- end -}}
    {{- if $gm -}}
      {{- $fields = coll.Append (coll.Dict "name" "Gamemode" "value" $gm "inline" true) $fields -}}
    {{- end -}}
    {{- if eq $.Status "resolved" -}}
      {{- $dur := .EndsAt.Sub .StartsAt -}}
      {{- if gt $dur 0 -}}
        {{- $durStr := reReplaceAll "\\.\\d+s" "s" (printf "%v" $dur) -}}
        {{- if not (eq $durStr "0s") -}}
        {{- $fields = coll.Append (coll.Dict "name" "Duration" "value" $durStr "inline" false) $fields -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $fields = coll.Append (coll.Dict "name" "Grafana" "value" (printf "[View alert](%s)" .ExternalURL) "inline" false) $fields -}}
  {{- $fields | data.ToJSON -}}
{{ end }}
```

### How it looks (Custom Payload)

**Firing — Critical**

```
╔═══════════════════════════════════════════════╗
║ 🚨 [FIRING] Server Overloaded                   ║
╠═══════════════════════════════════════════════╣
║ Server Overloaded                               ║
║ Frame time exceeds tick interval. Server can't  ║
║ keep up with configured tick rate.              ║
║───────────────────────────────────────────────║
║ Server: gmod-server (myserver.local) • Map: gm_construct • Gamemode: darkrp║
║───────────────────────────────────────────────║
║ Grafana: 🔗 View alert                         ║
╚═══════════════════════════════════════════════╝
```

**Firing — Info**

```
╔═══════════════════════════════════════════════╗
║ ℹ️ [FIRING] Server is empty                     ║
╠═══════════════════════════════════════════════╣
║ Server is empty                                ║
║ No players connected for at least 5 minutes.   ║
║───────────────────────────────────────────────║
║ Server: gmod-server (myserver.local) • Map: gm_construct • Gamemode: darkrp║
║───────────────────────────────────────────────║
║ Grafana: 🔗 View alert                         ║
╚═══════════════════════════════════════════════╝
```

**Resolved**

```
╔═══════════════════════════════════════════════╗
║ ✅ [RECOVERED] Server Overloaded                ║
╠═══════════════════════════════════════════════╣
║ Server Overloaded                               ║
║ ✅ Recovered after 4m 23s                       ║
║───────────────────────────────────────────────║
║ Server: gmod-server (myserver.local) • Map: gm_construct • Gamemode: darkrp║
║───────────────────────────────────────────────║
║ Duration: 4m 23s                                ║
║───────────────────────────────────────────────║
║ Grafana: 🔗 View alert                         ║
╚═══════════════════════════════════════════════╝
```

### Pros & cons

| Pro | Con |
|-----|-----|
| Full control over embed — fields, color, timestamp, footer | Slightly more setup (Webhook + Custom Payload) |
| Everything inside the embed (no loose text) | Uses namespaced functions (`coll.Dict`, `data.JSON`, `tmpl.Inline`, `tmpl.Exec`) |
| Multiple fields per alert, severity-colored | |

---

## Which to choose

| You want... | Use |
|-------------|-----|
| Quick setup, default embed is enough | **A — Discord Native** |
| Custom embed with fields, everything inside | **B — Webhook Custom Payload** |
| Both — test which looks better | **Both** — they share the same Notification Template group |

---

## Troubleshooting

### Message doesn't arrive in Discord

- Verify the webhook URL is correct (Grafana → Contact point → URL)
- Check Discord → Server Settings → Integrations → Webhooks → your webhook exists
- Grafana must have outbound internet access to `discord.com`

### Template syntax error

- In the **Templates** tab, edit the `gTelemetry Discord` group → click **Refresh preview**
- The preview shows errors inline — fix them and re-save
- Common issues: unclosed `{{ end }}`, missing quotes, invalid function names

### Custom Payload: embed shows as raw JSON text

- The Custom Payload template must produce **valid JSON** — use `data.ToJSONPretty` for structured output
- Check that the Payload Template field contains the full `{{ template "gtelemetry.custom" . }}` call
- Namespaced functions (`coll.*`, `data.*`, `tmpl.*`) require Grafana 12+

### Map or Gamemode field missing

- The template tries multiple label variants: `gmod.map` / `gmod_map` / `server.map` / `server_map`, and `gmod.gamemode` / `gmod_gamemode` / `server.gamemode` / `server_gamemode`.
- If none exist in the alert `.Labels`, the field is simply omitted (no fallback text shown).

### Server field shows "n/a"

- The template tries `service.name`, `service_name`, then falls back to `"n/a"`.
- If `host.name` or `host_name` exists, it's appended in parentheses: `gmod-server (myserver.local)`.
- Add the label `service.name` to each alert rule: **Alerting → Alert rules → [your rule] → Labels** → add `service.name` = your server name (e.g. `gmod-server`).

### Discord Native: embed shows default title

- Verify **Use custom message** is enabled in the Discord contact point
- **Title** field must contain `{{ template "gtelemetry.title" . }}` (exact)
- Check the Notification Template group on the Templates tab
