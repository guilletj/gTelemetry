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
// Uncomment the two blocks below AND the logs line in the
// receiver output above. Then set gtelemetry_log_enabled 1.
// ════════════════════════════════════════════════════════════

// otelcol.processor.batch "logs" {
//     timeout = "5s"
//     send_batch_size = 500
//     output {
//         logs = [loki.write.default.receiver]
//     }
// }
//
// loki.write "default" {
//     endpoint {
//         url = "http://localhost:3100/loki/api/v1/push"
//     }
// }
