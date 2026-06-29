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
    {{- $severity := "" -}}
    {{- range .Alerts -}}
      {{- if eq .Labels.severity "Critical" -}}{{- $severity = "Critical" -}}{{- end -}}
    {{- end -}}
    {{- if eq $severity "Critical" -}}🚨{{- else -}}⚠️{{- end -}}
    [FIRING] {{ (index .Alerts 0).Annotations.summary }}
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
  **Server:** {{ $server }}{{ if index .Labels "gmod.map" }} • **Map:** {{ index .Labels "gmod.map" }}{{ end }}
  {{- if eq $.Status "resolved" }}
  **Duration:** {{ template "gtelemetry.duration" . }}
  {{- end -}}
  {{- end -}}
{{ end }}
```

### How it looks (Discord Native)

```
Frame time (0.029s) exceeds tick interval (0.015s).
Server cannot keep up with configured tick rate.

Server: gmod-server • Map: gm_construct

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
  {{- range .Alerts -}}
    {{- if eq .Labels.severity "Critical" -}}{{- $color = 15548997 -}}{{- end -}}
  {{- end -}}
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
    {{- $fields = coll.Append (coll.Dict "name" "Server" "value" $server "inline" true) $fields -}}
    {{- if index .Labels "gmod.map" -}}
      {{- $fields = coll.Append (coll.Dict "name" "Map" "value" (index .Labels "gmod.map") "inline" true) $fields -}}
    {{- end -}}
    {{- if eq $.Status "resolved" -}}
      {{- $fields = coll.Append (coll.Dict "name" "Duration" "value" (tmpl.Inline `{{ template "gtelemetry.duration" . }}` .) "inline" false) $fields -}}
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
║ Server: gmod-server              Map: gm_construct║
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
║ Server: gmod-server          Map: gm_construct  ║
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

### Server field shows "n/a"

- The template looks for `service.name` (or `service_name`) in the alert `.Labels`. If neither exists, it falls back to `"n/a"`.
- Add the label `service.name` to each alert rule: **Alerting → Alert rules → [your rule] → Labels** → add `service.name` = your server name (e.g. `gmod-server`).

### Discord Native: embed shows default title

- Verify **Use custom message** is enabled in the Discord contact point
- **Title** field must contain `{{ template "gtelemetry.title" . }}` (exact)
- Check the Notification Template group on the Templates tab
