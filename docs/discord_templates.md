# gTelemetry — Discord Alert Templates

Go templating for Grafana 11+ Discord contact point. One generic template for all gTelemetry alerts, color-coded by severity.

## Prerequisites

- Grafana 11+ (Discord contact point built-in, no plugin required)
- Discord webhook URL (Server Settings → Integrations → Webhooks → New Webhook)

## Setup

### 1. Create a Discord Webhook

1. Open your Discord server settings
2. Go to **Integrations** → **Webhooks** → **New Webhook**
3. Name it `gTelemetry Alerts` and select the channel
4. Copy the **Webhook URL** (`https://discord.com/api/webhooks/...`)

### 2. Create a Grafana Contact Point

1. In Grafana, go to **Alerting** → **Contact points** → **New contact point**
2. Set:
   - **Name**: `gTelemetry Discord`
   - **Integration**: Discord
   - **Discord URL**: your webhook URL
3. Toggle **Optional Discord settings** → **Use custom message**
4. Paste the template below into the **Content** field
5. Click **Test** → choose any alert rule → verify the message appears in Discord
6. **Save contact point**

### 3. Create a Notification Policy

1. Go to **Alerting** → **Notification policies** → **New policy**
2. Set:
   - **Label**: add matcher `service.name = gmod-server` (or your `gtelemetry_service_name`)
   - **Contact point**: `gTelemetry Discord`
   - **Override grouping**: optionally set `...` if you want per-alert notifications
3. Click **Save**

---

## Single Generic Template

Copy this into the **Content** field of the Discord contact point (with **Use custom message** enabled):

```go
{{ define "alert_color" }}
  {{- if eq .Status "resolved" -}} 5763719
  {{- else -}}
    {{- $severity := "" -}}
    {{- range .Alerts -}}
      {{- if eq .Labels.severity "Critical" -}}{{- $severity = "Critical" -}}{{- end -}}
    {{- end -}}
    {{- if eq $severity "Critical" -}}15548997
    {{- else -}}15844367
    {{- end -}}
  {{- end -}}
{{- end -}}

{{ define "severity_emoji" }}
  {{- if eq .Status "resolved" -}}✅
  {{- else -}}
    {{- $severity := "" -}}
    {{- range .Alerts -}}
      {{- if eq .Labels.severity "Critical" -}}{{- $severity = "Critical" -}}{{- end -}}
    {{- end -}}
    {{- if eq $severity "Critical" -}}🚨
    {{- else -}}⚠️
    {{- end -}}
  {{- end -}}
{{- end -}}

{{ define "alert_duration" -}}
  {{- if and .StartsAt .EndsAt -}}
    {{- $dur := .EndsAt.Sub .StartsAt -}}
    {{- $hours := ($dur.Hours) | int -}}
    {{- $minutes := (mod ($dur.Minutes) 60) | int -}}
    {{- $seconds := (mod ($dur.Seconds) 60) | int -}}
    {{- if gt $hours 0 -}}{{$hours}}h {{end -}}
    {{- if gt $minutes 0 -}}{{$minutes}}m {{end -}}
    {{$seconds}}s
  {{- end -}}
{{- end -}}

{{ define "alert_status_tag" -}}
  {{- if eq .Status "resolved" -}}RECOVERED
  {{- else -}}{{ .Status | upper }}
  {{- end -}}
{{- end -}}

{{ define "alert_embed" -}}
{
  "embeds": [
    {
      "title": "{{ template "severity_emoji" . }} [{{ template "alert_status_tag" . }}] {{ (index .Alerts 0).Annotations.summary }}",
      "color": {{ template "alert_color" . }},
      "fields": [
        {{- range .Alerts }}
        {
          "name": "{{ .Annotations.summary }}",
          "value": "{{ if eq $.Status "resolved" }}✅ Recovered after {{ template "alert_duration" . }}{{ else }}{{ .Annotations.description }}{{ end }}",
          "inline": false
        },
        {{- if .Values }}
        {
          "name": "{{ if eq $.Status "resolved" }}Final Value{{ else }}Value{{ end }}",
          "value": "{{ range $k, $v := .Values }}{{ $k }} = {{ $v }}\n{{ end }}",
          "inline": true
        },
        {{- end }}
        {
          "name": "Server",
          "value": "{{ index .Labels "service.name" }}",
          "inline": true
        },
        {{- if index .Labels "gmod.map" }}
        {
          "name": "Map",
          "value": "{{ index .Labels "gmod.map" }}",
          "inline": true
        },
        {{- end }}
        {{- if eq $.Status "resolved" }}
        {
          "name": "Duration",
          "value": "{{ template "alert_duration" . }}",
          "inline": true
        },
        {{- end }}
        {{- end }}
        {
          "name": "Grafana",
          "value": "[View alert]({{ .ExternalURL }})",
          "inline": false
        }
      ],
      "timestamp": "{{ if eq .Status "resolved" }}{{ (index .Alerts 0).EndsAt }}{{ else }}{{ (index .Alerts 0).StartsAt }}{{ end }}"
    }
  ]
}
{{- end -}}

{{ template "alert_embed" . }}
```

> **Gotcha**: If you use **Notification policies** that group alerts, `.Alerts` will contain multiple items. The template iterates over them and renders one field set per alert in a single embed. For ungrouped alerts (recommended for simplicity), only one alert is in the list.

---

## How It Looks

### Firing — Critical

![Discord Critical Alert](https://img.shields.io/badge/discord-embed-red)

```
🚨 [FIRING] Server overloaded — tick_duration = 1.45
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Server Overloaded:
Frame time (0.029s) exceeds tick interval (0.015s).
Server cannot keep up with configured tick rate.

Value:  B8 = 1.45
Server: gmod-server
Map:    gm_construct

Grafana: 🔗 View alert
```

### Firing — Warning

```
⚠️ [FIRING] Possible Lua memory leak
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Possible Lua memory leak:
Lua memory grew by 120MB in the last 10 minutes.
If sustained, this will crash the server.

Value:  B8 = 125829120
Server: gmod-server
Map:    gm_construct

Grafana: 🔗 View alert
```

### Resolved

```
✅ [RECOVERED] Server overloaded
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Server Overloaded:
✅ Recovered after 4m 23s

Final Value:  B8 = 0.85
Server:       gmod-server
Map:          gm_construct
Duration:     4m 23s

Grafana: 🔗 View alert
```

---

## Testing

1. In the contact point, click **Test**
2. Choose an existing alert rule (e.g., `Server Overloaded`)
3. Click **Send test notification**
4. Check your Discord channel for the message

If the test doesn't show the embeds as expected, click **Show preview** to see the rendered JSON before sending.

## Troubleshooting

### Message doesn't arrive in Discord

- Verify the webhook URL is correct (Grafana Contact point → Discord URL)
- Check Discord → Server Settings → Integrations → Webhooks → your webhook exists and is not deleted
- Grafana must have outbound internet access to `discord.com`

### Embed shows raw JSON instead of formatted message

The template must produce valid JSON. Click **Show preview** in the Discord contact point to see the rendered output, then validate it at a JSON validator. Common issues:
- Trailing commas in JSON
- Missing quotes around strings
- Unescaped quotes inside strings (use `\"` or `{{ "" }}`)

### Template renders empty

- Verify **Use custom message** is enabled
- Make sure there are no syntax errors in the Go template — Grafana silently falls back to default if the template fails
- Keep the template simple if you're unsure, then add complexity gradually
