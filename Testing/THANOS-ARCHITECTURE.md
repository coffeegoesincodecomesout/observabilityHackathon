# Understanding Thanos in OpenShift Monitoring

## Why We Use Thanos

In OpenShift 4.x, the monitoring stack uses **Thanos** to provide a scalable, multi-tenant monitoring solution. Understanding this architecture is key to properly querying metrics and checking alerts.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Monitoring Stack                │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────┐          ┌──────────────────────┐
│  Platform Monitoring │          │ User Workload        │
│  (openshift-         │          │ Monitoring           │
│   monitoring)        │          │ (openshift-user-     │
│                      │          │  workload-monitoring)│
│                      │          │                      │
│  ┌────────────────┐ │          │  ┌────────────────┐  │
│  │ Prometheus     │ │          │  │ Prometheus     │  │
│  │ (platform)     │ │          │  │ (user-workload)│  │
│  └────────┬───────┘ │          │  └────────┬───────┘  │
│           │         │          │           │          │
│  ┌────────▼───────┐ │          │  ┌────────▼───────┐  │
│  │ Thanos Sidecar │ │          │  │ Thanos Sidecar │  │
│  └────────┬───────┘ │          │  └────────┬───────┘  │
│           │         │          │           │          │
└───────────┼─────────┘          └───────────┼──────────┘
            │                                │
            │         ┌──────────────────────┤
            │         │                      │
            │    ┌────▼────────┐    ┌────────▼────────┐
            └───►│   Thanos    │    │  Thanos Ruler   │
                 │   Querier   │    │  (User Workload)│
                 └─────────────┘    └─────────────────┘
                        │                    │
                        │                    │
                  Unified Metrics      Alert Evaluation
                     Queries           (PrometheusRules)
```

## Components

### 1. Prometheus Instances
- **Platform Prometheus**: Monitors OpenShift platform components
- **User Workload Prometheus**: Scrapes metrics from user applications (our test apps)
- Each has a Thanos Sidecar that exposes metrics via gRPC

### 2. Thanos Querier
- **Location**: `openshift-monitoring` namespace
- **Purpose**: Aggregates and queries metrics from ALL Prometheus instances
- **Port**: 9091 (HTTP), 10901 (gRPC)
- **Use for**: Querying metrics across platform and user workloads

### 3. Thanos Ruler
- **Location**: `openshift-user-workload-monitoring` namespace  
- **Purpose**: Evaluates PrometheusRules and manages alerts for user workloads
- **Port**: 10902 (HTTP API)
- **Use for**: Checking alert status, viewing fired alerts

### 4. Thanos Sidecar
- Runs alongside each Prometheus instance
- Exposes Prometheus data via Thanos gRPC API
- Enables query aggregation by Thanos Querier

## Why Not Query Prometheus Directly?

While you CAN query Prometheus directly, you SHOULD use Thanos because:

1. **Thanos Querier** provides a unified view across all Prometheus instances
2. **Thanos Ruler** is where user workload alerts are actually evaluated
3. Querying Prometheus directly only shows data from that specific instance
4. OpenShift's architecture is designed for Thanos-based queries

## Practical Examples

### Query Metrics (Use Thanos Querier)

```bash
# Get Thanos Querier pod
THANOS_POD=$(oc get pod -n openshift-monitoring -l app.kubernetes.io/name=thanos-query -o name | head -1 | cut -d/ -f2)

# Query metrics via API
oc exec -n openshift-monitoring $THANOS_POD -c thanos-query -- \
  curl -s 'http://localhost:9090/api/v1/query?query=ping_request_count'

# Or port-forward to access UI
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
# Visit: http://localhost:9091
```

### Check Alerts (Use Thanos Ruler)

```bash
# Check alerts via Thanos Ruler API
oc exec -n openshift-user-workload-monitoring thanos-ruler-user-workload-0 -c thanos-ruler -- \
  curl -s 'http://localhost:10902/api/v1/alerts'

# Or use our script
./check-alerts.sh
```

### Access UIs

```bash
# Thanos Querier (metrics)
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
# Visit: http://localhost:9091

# Thanos Ruler (alerts)  
oc port-forward -n openshift-user-workload-monitoring svc/thanos-ruler 9092:9092
# Visit: http://localhost:9092

# Or use OpenShift Console
oc get console cluster -o jsonpath='{.status.consoleURL}'
# Navigate to: Observe → Metrics (uses Thanos Querier)
# Navigate to: Observe → Alerting (uses Thanos Ruler)
```

## How Our Test Apps Fit In

1. **ServiceMonitors** tell Prometheus where to scrape metrics from our apps
2. **Prometheus** (user-workload) scrapes metrics every 30 seconds
3. **Thanos Sidecar** makes those metrics available
4. **Thanos Querier** can query those metrics
5. **PrometheusRules** define alert conditions
6. **Thanos Ruler** evaluates those rules and fires alerts

## Data Flow

```
Test App (port 8090)
    │
    │ exposes /metrics
    │
    ▼
ServiceMonitor (tells Prometheus what to scrape)
    │
    ▼
Prometheus (scrapes every 30s)
    │
    ├──► Stores metrics locally
    │
    └──► Thanos Sidecar (exposes via gRPC)
            │
            ├──► Thanos Querier (for queries)
            │
            └──► Thanos Ruler (evaluates PrometheusRules)
                     │
                     └──► Fires alerts when conditions met
```

## Common Mistakes

❌ **Wrong**: Query Prometheus directly for user workload metrics
```bash
oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090
```

✅ **Right**: Query via Thanos Querier
```bash
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
```

❌ **Wrong**: Check for alerts in Prometheus
```bash
oc exec prometheus-user-workload-0 -- curl http://localhost:9090/api/v1/alerts
```

✅ **Right**: Check alerts in Thanos Ruler
```bash
oc exec thanos-ruler-user-workload-0 -c thanos-ruler -- curl http://localhost:10902/api/v1/alerts
```

## For the Hackathon Demo

When demonstrating the observability stack:

1. **Explain the architecture**: Show how Thanos provides multi-tenancy
2. **Use Thanos Querier**: Query metrics through the proper component
3. **Show Thanos Ruler**: Demonstrate that alerts are evaluated there
4. **Highlight the benefits**: Unified queries, multi-tenancy, scalability

## References

- [OpenShift Monitoring Overview](https://docs.openshift.com/container-platform/latest/monitoring/monitoring-overview.html)
- [Thanos Project](https://thanos.io/)
- [User Workload Monitoring](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
