# Jaeger with Service Performance Monitoring (SPM) Demo

This repository contains a complete, working implementation of Jaeger with Service Performance Monitoring (SPM) functionality deployed in Kubernetes. It demonstrates how to configure and use Jaeger's SPM features to monitor service performance metrics derived from traces.

## Overview

Service Performance Monitoring (SPM) in Jaeger allows you to:
- View service call rates, error rates, and latency percentiles
- Analyze performance trends over time
- Drill down from metrics to individual traces
- Identify performance bottlenecks across your services

This implementation includes:
- Jaeger all-in-one with SPM functionality enabled
- Prometheus for metrics collection and storage
- HotROD demo application for generating traces
- Traffic generation script for demonstration

## Architecture

The implementation uses the following components:
- **Jaeger**: Configured with the spanmetrics processor to convert traces to metrics
- **Prometheus**: Scrapes metrics from Jaeger and provides storage for SPM dashboards
- **HotROD**: Demo application that generates distributed traces

The data flow is as follows:
1. HotROD generates traces and sends them to Jaeger
2. Jaeger processes traces through the spanmetrics processor
3. Metrics are exposed on port 8889
4. Prometheus scrapes metrics from Jaeger
5. Jaeger UI queries Prometheus to display SPM dashboards

## Quick Start

### Prerequisites
- Kubernetes cluster (Minikube, kind, or any other Kubernetes cluster)
- kubectl configured to access your cluster

### One-Command Demo

To deploy and run the complete demo:

```bash
./run-demo.sh
```

This script will:
- Deploy all components to your Kubernetes cluster
- Set up port forwarding for the UIs
- Generate sample traffic to create traces and metrics
- Provide access information for all components

### Manual Deployment

If you prefer to deploy manually:

1. Deploy all components:
   ```bash
   kubectl apply -k kubernetes/base/jaeger-spm
   ```

2. Access the UIs:
   ```bash
   # Jaeger UI
   kubectl port-forward svc/jaeger 16686:16686
   
   # Prometheus
   kubectl port-forward svc/prometheus 9090:9090
   
   # HotROD application
   minikube service hotrod --url
   ```

3. Generate traffic:
   ```bash
   # Get HotROD URL
   HOTROD_URL=$(minikube service hotrod --url)
   
   # Run traffic generator
   HOTROD_HOST=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f1) \
   HOTROD_PORT=$(echo $HOTROD_URL | sed 's|http://||' | cut -d':' -f2) \
   ./generate_traffic.sh
   ```

## Exploring SPM Features

1. **In Jaeger UI (http://localhost:16686)**:
   - Navigate to the "Service Performance" tab
   - View metrics for call rates, error rates, and latency percentiles
   - Click on specific service calls to drill down into trace details

2. **In Prometheus (http://localhost:9090)**:
   - Query for metrics like `traces_span_metrics_calls_total`
   - Analyze trends in service performance

## Configuration Details

### Jaeger Configuration

The Jaeger configuration enables SPM through the spanmetrics processor:

```yaml
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger_storage_exporter, spanmetrics]
    metrics/spanmetrics:
      receivers: [spanmetrics]
      exporters: [prometheus]

connectors:
  spanmetrics:

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
```

### Prometheus Configuration

Prometheus is configured to scrape metrics from Jaeger:

```yaml
scrape_configs:
  - job_name: aggregated-trace-metrics
    static_configs:
      - targets: ['jaeger:8889']
    metrics_path: /metrics
  - job_name: jaeger-metrics
    static_configs:
      - targets: ['jaeger:8889']
    metrics_path: /metrics
```

## Troubleshooting

If you encounter issues:

1. **No metrics in Prometheus**:
   - Verify Jaeger is exposing metrics: `kubectl exec -it <prometheus-pod> -- wget -qO- jaeger:8889/metrics`
   - Check Prometheus targets: http://localhost:9090/targets

2. **No traces in Jaeger**:
   - Ensure HotROD is configured to send traces to Jaeger
   - Check HotROD logs: `kubectl logs <hotrod-pod>`

## License

This project is licensed under the Apache License 2.0 - see the LICENSE file for details.

## Acknowledgments

This demo was created as part of an LFX project to implement Service Performance Monitoring with Jaeger.
