# gTelemetry — Discord Alert Templates

Go templating for Grafana 13+ Discord contact point. Uses the Notification Templates system (Templates tab) to define reusable templates for embed title and message content, color-coded by severity.

## Prerequisites

- Grafana 13+ (Discord contact point built-in, no plugin required)
- Discord webhook URL (Server Settings → Integrations → Webhooks → New Webhook)

## Setup

### 1. Create a Discord Webhook

1. Open your Discord server settings
2. Go to **Integrations** → **Webhooks** → **New Webhook**
3. Name it `gTelemetry Alerts` and select the channel
4. Copy the **Webhook URL** (`https://discord.com/api/webhooks/...`)

### 2. Create a Notification Template Group

1. In Grafana, go to **Alerts & IRM** → **Alerting** → **Notification configuration**
2. Select the **Templates** tab
3. Click **+ New notification template group**
4. **Name**: `gTelemetry Discord`
5. Paste the template block below into the **Content** field
6. Click **Save notification template group**

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

{{ define "gtelemetry.message" -}}
  {{- range $i, $alert := .Alerts -}}
  {{- if $i }}
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {{ end -}}
  **{{ .Annotations.summary }}**
  {{ .Annotations.description }}
  {{- if .Values }}**Value:** {{ range $k, $v := .Values }}{{ $k }} = {{ $v }}{{ end }}
  {{ end -}}
  **Server:** {{ index .Labels "service.name" }}
  {{- if index .Labels "gmod.map" }}
  **Map:** {{ index .Labels "gmod.map" }}
  {{- end -}}
  {{- if eq $.Status "resolved" }}
  **Duration:** {{ template "gtelemetry.duration" . }}
  {{- end -}}
  {{- end -}}
  **[View alert]({{ .ExternalURL }})**
{{ end }}
```

### 3. Create a Grafana Contact Point

1. In Grafana, go to **Alerts & IRM** → **Alerting** → **Contact points** → **New contact point**
2. Set:
   - **Name**: `gTelemetry Discord`
   - **Integration**: Discord
   - **Discord URL**: your webhook URL
3. Toggle **Optional Discord settings** → **Use custom message**
4. Set:
   - **Title**: `{{ template "gtelemetry.title" . }}`
   - **Message Content**: `{{ template "gtelemetry.message" . }}`
5. Click **Test** → choose any alert rule → verify the message appears in Discord
6. **Save contact point**

### 4. Create a Notification Policy

1. Go to **Alerting** → **Notification policies** → **New policy**
2. Set:
   - **Label**: add matcher `service.name = gmod-server` (or your `gtelemetry_service_name`)
   - **Contact point**: `gTelemetry Discord`
   - **Override grouping**: optionally set `...` if you want per-alert notifications
3. Click **Save**

---

## How It Looks

### Firing — Critical

```
🚨 [FIRING] Server overloaded — tick_duration = 1.45

Server Overloaded:
Frame time (0.029s) exceeds tick interval (0.015s).
Server cannot keep up with configured tick rate.

Server: gmod-server
Map:    gm_construct

View alert 🔗
```

### Firing — Warning

```
⚠️ [FIRING] Possible Lua memory leak

Possible Lua memory leak:
Lua memory grew by 120MB in the last 10 minutes.
If sustained, this will crash the server.

Server: gmod-server
Map:    gm_construct

View alert 🔗
```

### Resolved

```
✅ [RECOVERED] Server overloaded

Server Overloaded:
✅ Recovered after 4m 23s

Server:   gmod-server
Map:      gm_construct
Duration: 4m 23s

View alert 🔗
```

---

## Testing

1. In the contact point, click **Test**
2. Choose an existing alert rule (e.g., `Server Overloaded`)
3. Click **Send test notification**
4. Check your Discord channel for the message

To preview the template output before saving, go to **Templates** tab → edit the `gTelemetry Discord` template group → click **Refresh preview**.

---

## Troubleshooting

### Message doesn't arrive in Discord

- Verify the webhook URL is correct (Grafana Contact point → Discord URL)
- Check Discord → Server Settings → Integrations → Webhooks → your webhook exists and is not deleted
- Grafana must have outbound internet access to `discord.com`

### Embed shows default title instead of custom

- Verify **Use custom message** is enabled in the Discord contact point
- Make sure the **Title** field is set to `{{ template "gtelemetry.title" . }}` (exact string)
- Check the Notification Template group exists and has no syntax errors — use **Refresh preview** on the Templates tab

### Message content appears empty

- Verify **Message Content** field is set to `{{ template "gtelemetry.message" . }}`
- Check the template group compiles: navigate to **Templates** tab → edit `gTelemetry Discord` → click **Refresh preview**
- If the preview shows nothing, check for template syntax errors in the Content field

### Notification Templates vs inline custom message

Grafana's Discord integration uses the Title and Message Content fields **only as plain text content**. The embed is auto-constructed by Grafana (title, footer, color, URL). The Notification Templates approach (recommended) keeps templates in a separate reusable group, avoids inline `define` quirks, and supports preview.
