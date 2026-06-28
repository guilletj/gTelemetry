// Example Grafana Alloy configuration for gTelemetry
// Save this as config.alloy and run: alloy run config.alloy

// ════════════════════════════════════════════════════════════
// OTLP Receiver — accepts metrics (and optionally logs)
// from gTelemetry via HTTP on port 4318
// ════════════════════════════════════════════════════════════
otelcol.receiver.otlp "gmod" {
    http {
        endpoint = "0.0.0.0:4318"
    }

    output {
        metrics = [otelcol.processor.batch.default.input]
        // Uncomment for Loki log support (see Optional: Loki section below):
        // logs    = [otelcol.processor.batch.logs.input]
    }
}

// ════════════════════════════════════════════════════════════
// Metrics pipeline — Prometheus remote_write
// ════════════════════════════════════════════════════════════
otelcol.processor.batch "default" {
    timeout = "5s"
    send_batch_size = 1000

    output {
        metrics = [otelcol.exporter.prometheus.default.input]
    }
}

otelcol.exporter.prometheus "default" {
    // Convert OTLP resource attributes (host.name, gmod.map, gmod.gamemode,
    // service.name, service.version) to Prometheus labels.
    // REQUIRED when multiple servers send to the same Alloy — without it every
    // server produces the same label-less time series, causing data collisions.
    // Safe for single-server setups too (low-cardinality attributes only).
    resource_to_telemetry_conversion = true

    // Propagate OTLP metric descriptions as Prometheus HELP strings.
    // Requires a backend that supports metadata in remote write (Mimir, Prometheus 3.x+).
    // Without this, descriptions are dropped — visible in Grafana's metric browser only when set.
    honor_metadata = true

    forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
    endpoint {
        url = "http://localhost:9090/api/v1/write"
        // For Grafana Mimir:
        // url = "http://localhost:9009/api/v1/push"
    }
}

// ════════════════════════════════════════════════════════════
// Optional: Export to InfluxDB (via OTLP HTTP)
// Uncomment to use InfluxDB instead of or alongside Prometheus.
// ============================================================
// To use both Prometheus AND InfluxDB, add the InfluxDB exporter
// to the batch processor's output.metrics array above.
// ============================================================

// otelcol.exporter.otlphttp "influxdb" {
//     client {
//         endpoint = "http://localhost:8086/api/v2/write"
//         headers = {
//             "Authorization" = "Token YOUR_INFLUXDB_TOKEN",
//         }
//     }
// }

// ════════════════════════════════════════════════════════════
// Optional: Loki log pipeline
// Uncomment the blocks below AND the logs line in the
// receiver output above. Then set gtelemetry_log_enabled 1.
//
// otelcol.exporter.loki converts OTel logs → Loki format.
// Direct wiring (otelcol.* → loki.write) fails because
// otelcol.Consumer ≠ loki.LogsReceiver.
// ════════════════════════════════════════════════════════════

// otelcol.processor.batch "logs" {
//     timeout = "5s"
//     send_batch_size = 500
//     output {
//         logs = [otelcol.exporter.loki.default.input]
//     }
// }
//
// otelcol.exporter.loki "default" {
//     forward_to = [loki.write.default.receiver]
// }
//
// loki.write "default" {
//     endpoint {
//         url = "http://localhost:3100/loki/api/v1/push"
//     }
// }
