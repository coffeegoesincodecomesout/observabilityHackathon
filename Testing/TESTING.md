# OpenShift 4.22 Observability Testing Guide

This directory contains scripts to test and verify the observability stack deployment for the hackathon.

## Running the Tests

All scripts are located in the `Testing/` directory. Either cd into the directory first:
```bash
cd Testing
./test-observability.sh
```

Or run from the repository root:
```bash
./Testing/test-observability.sh
```

## Overview

The deployment includes:
- **Metrics**: User Workload Monitoring (Prometheus)
- **Logs**: Cluster Logging + Loki
- **Traces**: OpenTelemetry + Tempo
- **Storage**: ODF/Noobaa
- **Test Apps**: 
  - `ns1-uwl`: Single app with metrics, logs, and traces
  - `ns2-uwl`: Frontend + Backend apps with full observability

## Test Scripts

### 1. `test-observability.sh` - Complete Test Suite ⭐

Comprehensive end-to-end test that:
- ✅ Verifies all deployments are running
- ✅ Checks observability components are configured
- ✅ Tests application endpoints
- ✅ Generates traffic for 3 minutes
- ✅ Verifies metrics collection
- ✅ Checks that alerts fire
- ✅ Validates log collection
- ✅ Confirms traces are sent to collector

**Usage:**
```bash
./test-observability.sh
```

**Duration:** ~5 minutes (3 min traffic + 1.5 min verification)

### 2. `verify-stack.sh` - Stack Component Verification

Quick check of all observability stack components:
- Storage (ODF/Noobaa)
- Logging Stack (Loki, Collector)
- Metrics Stack (Prometheus, Thanos Ruler)
- Tracing Stack (OpenTelemetry, Tempo)
- Application deployments
- ServiceMonitors, PrometheusRules, AlertingRules

**Usage:**
```bash
./verify-stack.sh
```

**Duration:** ~10 seconds

### 3. `generate-continuous-traffic.sh` - Traffic Generator

Continuously generates HTTP requests to test applications to keep metrics flowing and alerts firing.

**Usage:**
```bash
# Default: 2 requests/second
./generate-continuous-traffic.sh

# Custom rate: 5 requests/second
./generate-continuous-traffic.sh 5

# Stop with Ctrl+C
```

**Use Cases:**
- Keep alerts in firing state during demos
- Generate sustained load for testing
- Populate metrics dashboards with data

### 4. `check-alerts.sh` - Alert Status Check

Quick check of all alert states and current metric values.

**Usage:**
```bash
./check-alerts.sh
```

Shows:
- Status of all Prometheus metric alerts (firing/pending/inactive)
- Current values of monitored metrics
- Loki log-based alert configurations

## Configured Alerts

### NS1-UWL Alerts

**Metric Alert:**
- `TestappConnectionCount`: Fires when `ping_request_count > 0` for 1 minute

**Log Alert:**
- `TestappLogRallyCount`: Fires when log rate with "info" > 0.01 for 1 minute

### NS2-UWL Alerts

**Metric Alerts:**
- `TestappFrontendConnectionCount`: Fires when frontend `ping_request_count > 0` for 1 minute
- `TestappBackendResponseCount`: Fires when backend `ping_response_request_count > 0` for 1 minute

**Log Alerts:**
- `TestappFrontendLogRallyCount`: Fires when frontend log rate with "info" > 0.01 for 1 minute
- `TestappBackendLogResponseCount`: Fires when backend log rate with "info" > 0.01 for 1 minute

## Quick Testing Workflow

### For Hackathon Demo/Verification:

1. **Initial verification:**
   ```bash
   ./verify-stack.sh
   ```

2. **Run full test suite:**
   ```bash
   ./test-observability.sh
   ```

3. **Keep traffic flowing during demo:**
   ```bash
   # In a separate terminal
   ./generate-continuous-traffic.sh
   ```

4. **Check alert status anytime:**
   ```bash
   ./check-alerts.sh
   ```

### Manual Testing:

**Generate quick traffic burst:**
```bash
NS1_ROUTE=$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}')
NS2_ROUTE=$(oc get route threepilar-frontend-route -n ns2-uwl -o jsonpath='{.spec.host}')

# Continuous hits
watch -n 1 curl -s http://$NS1_ROUTE/ping
watch -n 1 curl -s http://$NS2_ROUTE/ping
```

**View live application logs:**
```bash
oc logs -n ns1-uwl -l app=threepilar-example -f
oc logs -n ns2-uwl -l app=threepilar-frontend -f
oc logs -n ns2-uwl -l app=threepilar-backend -f
```

**Access Thanos Querier UI (Proper Way):**
```bash
# Thanos Querier aggregates metrics from all Prometheus instances
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091
# Visit: http://localhost:9091
```

**Or access Prometheus directly (for debugging only):**
```bash
oc port-forward -n openshift-user-workload-monitoring prometheus-user-workload-0 9090:9090
# Visit: http://localhost:9090
# Note: Alerts are managed by Thanos Ruler, not Prometheus directly
```

**Access Tempo for traces:**
```bash
oc port-forward -n tempo svc/tempo-query-frontend 3200:3200
# Visit: http://localhost:3200
```

**Query metrics directly:**
```bash
oc exec -n openshift-user-workload-monitoring prometheus-user-workload-0 -c prometheus -- \
  promtool query instant http://localhost:9090 'ping_request_count'
```

**Check alert rules:**
```bash
# Prometheus metric alerts
oc get prometheusrule -n ns1-uwl example-alert -o yaml
oc get prometheusrule -n ns2-uwl example-alert -o yaml

# Loki log alerts
oc get alertingrule -n ns1-uwl threepilars-logging-alert -o yaml
oc get alertingrule -n ns2-uwl threepilars-ns2-logging-alert -o yaml
```

## Troubleshooting

### Alerts Not Firing

1. Ensure traffic is being generated:
   ```bash
   ./generate-continuous-traffic.sh
   ```

2. Wait at least 60 seconds (alerts have `for: 1m` clause)

3. Check metric values:
   ```bash
   ./check-alerts.sh
   ```

4. Verify ServiceMonitors are scraping:
   ```bash
   oc get servicemonitor -n ns1-uwl
   oc get servicemonitor -n ns2-uwl
   ```

### Metrics Not Appearing

1. Check if User Workload Monitoring is enabled:
   ```bash
   oc get prometheus user-workload -n openshift-user-workload-monitoring
   ```

2. Verify ServiceMonitor configuration:
   ```bash
   oc get servicemonitor -A
   ```

3. Check application pods are exposing metrics:
   ```bash
   POD=$(oc get pod -n ns1-uwl -l app=threepilar-example -o name | head -1)
   oc exec -n ns1-uwl $POD -- curl localhost:8090/metrics
   ```

### Logs Not Collecting

1. Verify cluster logging is running:
   ```bash
   oc get pods -n openshift-logging
   ```

2. Check collector daemonset:
   ```bash
   oc get daemonset collector -n openshift-logging
   ```

3. Verify application is logging:
   ```bash
   oc logs -n ns1-uwl -l app=threepilar-example --tail=20
   ```

### Traces Not Appearing

1. Check OpenTelemetry collector:
   ```bash
   oc get pods -n opentelemetry
   oc logs -n opentelemetry -l app.kubernetes.io/name=otel-collector
   ```

2. Verify Tempo is running:
   ```bash
   oc get pods -n tempo
   ```

3. Check OTLP endpoint is accessible from app namespaces:
   ```bash
   oc exec -n ns1-uwl deployment/threepilar-uwl-example-app -- \
     curl -v http://otel-collector.opentelemetry.svc.cluster.local:4317
   ```

## Expected Results

After running the test suite, you should see:

✅ All deployments healthy and ready  
✅ Observability stack components running  
✅ Applications responding to HTTP requests  
✅ Traffic successfully generated  
✅ Metrics scraped by Prometheus  
✅ At least 3 alerts in firing/pending state  
✅ Application logs visible and containing "info" entries  
✅ Traces sent to OpenTelemetry collector  

## OpenShift Console

Access the Observe section in the OpenShift console:

```bash
oc whoami --show-console
```

Navigate to:
- **Observe → Alerting** - View firing alerts
- **Observe → Metrics** - Query Prometheus metrics
- **Observe → Logs** - View application logs via Loki
- **Observe → Distributed Tracing** - View traces in Tempo (if UI plugin enabled)

## References

- Test App (ns1): https://github.com/coffeegoesincodecomesout/testapp-ThreePilars
- Test Frontend (ns2): https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-Frontend
- Test Backend (ns2): https://github.com/coffeegoesincodecomesout/testapp-ThreePilars-backend
