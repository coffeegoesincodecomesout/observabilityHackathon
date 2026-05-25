# Alert Summary

## Total Alerts: 7

### User Workload Metric Alerts (3) ✅ ALL FIRING

These are evaluated by **Thanos Ruler** in the `openshift-user-workload-monitoring` namespace:

| Alert Name | Namespace | Condition | Status | Where to Check |
|-----------|-----------|-----------|--------|----------------|
| TestappConnectionCount | ns1-uwl | `ping_request_count > 0` for 1m | 🔥 FIRING | Thanos Ruler (UWM) |
| TestappFrontendConnectionCount | ns2-uwl | `ping_request_count > 0` for 1m | 🔥 FIRING | Thanos Ruler (UWM) |
| TestappBackendResponseCount | ns2-uwl | `ping_response_request_count > 0` for 1m | 🔥 FIRING | Thanos Ruler (UWM) |

**Check with:**
```bash
./check-alerts.sh
# OR
oc exec -n openshift-user-workload-monitoring thanos-ruler-user-workload-0 -c thanos-ruler -- \
  curl -s 'http://localhost:10902/api/v1/alerts'
```

### Platform Metric Alert (1) ⚙️ CONFIGURED

This is evaluated by **Platform Prometheus** in the `openshift-monitoring` namespace:

| Alert Name | Namespace | Condition | Status | Where to Check |
|-----------|-----------|-----------|--------|----------------|
| TestappNetObservIncomingBandwidth | openshift-monitoring | Network traffic from ingress to ns1-uwl > 1 MBps for 30s | ⚙️ Configured | Platform Prometheus |

**Check with:**
```bash
./check-alerts.sh
# OR
oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- \
  curl -s 'http://localhost:9090/api/v1/alerts'
```

**To trigger this alert:**
Generate sustained high traffic to ns1-uwl app:
```bash
NS1_ROUTE=$(oc get route threepilar-example-route -n ns1-uwl -o jsonpath='{.spec.host}')
while true; do
  for i in {1..100}; do curl -s http://$NS1_ROUTE/ping > /dev/null & done
  sleep 1
done
```

### Loki Log-Based Alerts (3) ⚙️ CONFIGURED

These are evaluated by **Loki Ruler** and monitor log rates:

| Alert Name | Namespace | Condition | Type |
|-----------|-----------|-----------|------|
| TestappLogRallyCount | ns1-uwl | Log rate with "info" > 0.01 for 1m | Loki AlertingRule |
| TestappFrontendLogRallyCount | ns2-uwl | Frontend log rate with "info" > 0.01 for 1m | Loki AlertingRule |
| TestappBackendLogResponseCount | ns2-uwl | Backend log rate with "info" > 0.01 for 1m | Loki AlertingRule |

**Check configured rules:**
```bash
oc get alertingrule -n ns1-uwl threepilars-logging-alert -o yaml
oc get alertingrule -n ns2-uwl threepilars-ns2-logging-alert -o yaml
```

## Alert Architecture

### User Workload Monitoring (Prometheus Alerts)
```
PrometheusRule (ns1-uwl, ns2-uwl)
    ↓
User Workload Prometheus (scrapes metrics)
    ↓
Thanos Ruler (evaluates PrometheusRules) ← Check here!
    ↓
AlertManager (fires notifications)
```

### Platform Monitoring (NetObserv Alert)
```
PrometheusRule (openshift-monitoring)
    ↓
Platform Prometheus (scrapes NetObserv metrics)
    ↓
Platform Prometheus (evaluates rules) ← Check here!
    ↓
AlertManager (fires notifications)
```

### Log-Based Monitoring (Loki Alerts)
```
AlertingRule (ns1-uwl, ns2-uwl)
    ↓
Loki (collects logs)
    ↓
Loki Ruler (evaluates AlertingRules) ← Check here!
    ↓
AlertManager (fires notifications)
```

## Key Differences

| Component | API Version | Kind | Namespace | Evaluated By |
|-----------|-------------|------|-----------|--------------|
| User Workload Metric Alert | `monitoring.coreos.com/v1` | `PrometheusRule` | User namespace | Thanos Ruler (UWM) |
| Platform Metric Alert | `monitoring.coreos.com/v1` | `PrometheusRule` | openshift-monitoring | Platform Prometheus |
| Log Alert | `loki.grafana.com/v1` | `AlertingRule` | User namespace | Loki Ruler |

## Quick Access Commands

**Check all alerts:**
```bash
cd Testing
./check-alerts.sh
```

**Generate traffic to trigger alerts:**
```bash
./generate-continuous-traffic.sh
```

**Access UIs:**
```bash
# Thanos Querier (see all metrics)
oc port-forward -n openshift-monitoring svc/thanos-querier 9091:9091

# Thanos Ruler (user workload alerts)
oc port-forward -n openshift-user-workload-monitoring svc/thanos-ruler 9092:9092

# Platform Prometheus (platform alerts)
oc port-forward -n openshift-monitoring prometheus-k8s-0 9090:9090

# OpenShift Console
oc get console cluster -o jsonpath='{.status.consoleURL}'
# Navigate to: Observe → Alerting
```

## Files

| Alert | File Path | Type |
|-------|-----------|------|
| TestappConnectionCount | `09_ns1App/05_prometheusrule.yaml` | PrometheusRule |
| TestappFrontendConnectionCount | `10_ns2App/05_prometheusrule.yaml` | PrometheusRule |
| TestappBackendResponseCount | `10_ns2App/05_prometheusrule.yaml` | PrometheusRule |
| TestappNetObservIncomingBandwidth | `11_NetObserv/05_alert.yaml` | PrometheusRule |
| TestappLogRallyCount | `09_ns1App/04_alertingrule.yaml` | Loki AlertingRule |
| TestappFrontendLogRallyCount | `10_ns2App/06_alertingrule.yaml` | Loki AlertingRule |
| TestappBackendLogResponseCount | `10_ns2App/06_alertingrule.yaml` | Loki AlertingRule |
