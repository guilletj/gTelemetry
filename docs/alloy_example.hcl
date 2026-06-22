// Example Grafana Alloy configuration for gTelemetry
// Save this as config.alloy and run: alloy run config.alloy
//
// This configuration:
// 1. Receives OTLP metrics from gTelemetry via HTTP on port 4318
// 2. Batches metrics for efficiency
// 3. Exports to Prometheus (via remote_write) and/or InfluxDB
//
// Uncomment the exporter sections you need.

// ============================================================
// OTLP Receiver — accepts metrics from gTelemetry
// ============================================================
otelcol.receiver.otlp "gmod" {
    http {
        endpoint = "0.0.0.0:4318"
    }

    output {
        metrics = [otelcol.processor.batch.default.input]
    }
}

// ============================================================
// Batch Processor — groups metrics before export
// ============================================================
otelcol.processor.batch "default" {
    timeout = "5s"
    send_batch_size = 1000

    output {
        metrics = [
            // Uncomment the exporters you want to use:
            otelcol.exporter.prometheus.default.input,
            // otelcol.exporter.otlphttp.influxdb.input,
        ]
    }
}

// ============================================================
// OPTION A: Export to Prometheus
// ============================================================
// This exposes a /metrics endpoint that Prometheus can scrape,
// or you can use remote_write to push to Prometheus/Mimir.

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

// ============================================================
// OPTION B: Export to InfluxDB (via OTLP HTTP)
// ============================================================
// Uncomment this section if you want to use InfluxDB instead.
// InfluxDB 2.x+ supports OTLP natively.

// otelcol.exporter.otlphttp "influxdb" {
//     client {
//         endpoint = "http://localhost:8086/api/v2/write"
//         headers = {
//             "Authorization" = "Token YOUR_INFLUXDB_TOKEN",
//         }
//     }
// }

// ============================================================
// OPTION C: Export to both Prometheus AND InfluxDB
// ============================================================
// To use both, uncomment both exporters above and list them
// in the batch processor output.metrics array.
